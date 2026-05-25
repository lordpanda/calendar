import SwiftUI
import MapKit

struct LocationSearchView: View {
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language
    @StateObject private var search = LocationSearchModel()
    @State private var isSearchPresented = false
    @State private var selectedResult: LocationSearchResult?
    @State private var selectedLocation: LocatedSearchResult?
    @State private var resolvingResultID: String?
    @State private var unavailableResultIDs = Set<String>()
    @State private var cameraPosition: MapCameraPosition = .region(LocationSearchModel.defaultSearchRegion)

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    if let selectedLocation {
                        Section {
                            Map(position: $cameraPosition) {
                                Marker(selectedLocation.result.title, coordinate: selectedLocation.coordinate)
                            }
                            .frame(height: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                            .id(Self.mapPreviewID)
                        }
                    }

                    Section {
                        ForEach(search.results) { result in
                            Button {
                                resolve(result)
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(result.title)
                                            .foregroundStyle(.primary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        if let subtitle = subtitle(for: result) {
                                            Text(subtitle)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                    }

                                    if resolvingResultID == result.id {
                                        ProgressView()
                                    } else if selectedResult?.id == result.id {
                                        Image(systemName: "checkmark")
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(.blue)
                                    } else if unavailableResultIDs.contains(result.id) {
                                        Text(L.tr("No information", language: language))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 3)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                        }
                    }
                }
                .onChange(of: selectedLocation?.id) { _, id in
                    guard id != nil else { return }
                    withAnimation(.snappy(duration: 0.25)) {
                        proxy.scrollTo(Self.mapPreviewID, anchor: .top)
                    }
                }
                .tint(.primary)
                .navigationTitle(L.tr("Location", language: language))
                .searchable(
                    text: $search.query,
                    isPresented: $isSearchPresented,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: L.tr("Search maps", language: language)
                )
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.tr("Cancel", language: language)) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(L.tr("Done", language: language)) {
                        guard let selectedResult else { return }
                        onSelect(selectedResult.title)
                    }
                    .disabled(selectedResult == nil)
                }
            }
            .onAppear {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(250))
                    isSearchPresented = true
                }
            }
        }
    }

    private static let mapPreviewID = "location-map-preview"

    private func resolve(_ result: LocationSearchResult) {
        isSearchPresented = false
        selectedResult = result
        selectedLocation = nil
        unavailableResultIDs.remove(result.id)
        resolvingResultID = result.id

        Task {
            let located = await search.locatedResult(for: result)
            guard !Task.isCancelled else { return }
            resolvingResultID = nil

            guard let located else {
                unavailableResultIDs.insert(result.id)
                return
            }
            selectedResult = located.result
            selectedLocation = located
            cameraPosition = .region(MKCoordinateRegion(
                center: located.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
            ))
        }
    }

    private func subtitle(for result: LocationSearchResult) -> String? {
        if result.showsNoInformation {
            return L.tr("No information", language: language)
        }

        return result.subtitle.isEmpty ? nil : result.subtitle
    }
}

struct LocationSearchResult: Identifiable {
    let title: String
    let subtitle: String
    let latitude: Double?
    let longitude: Double?
    let completion: MKLocalSearchCompletion?

    init(
        title: String,
        subtitle: String,
        latitude: Double? = nil,
        longitude: Double? = nil,
        completion: MKLocalSearchCompletion? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.latitude = latitude
        self.longitude = longitude
        self.completion = completion
    }

    var id: String { "\(title)\n\(subtitle)" }

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var showsNoInformation: Bool {
        completion != nil && subtitle.localizedCaseInsensitiveContains("Search Nearby")
    }
}

struct LocatedSearchResult: Identifiable {
    let result: LocationSearchResult
    let coordinate: CLLocationCoordinate2D

    var id: String { result.id }
}

@MainActor
final class LocationSearchModel: NSObject, ObservableObject, @preconcurrency MKLocalSearchCompleterDelegate {
    @Published var query = "" {
        didSet {
            search()
        }
    }
    @Published var results: [LocationSearchResult] = []

    private let completer = MKLocalSearchCompleter()
    private var searchTask: Task<Void, Never>?
    private var fallbackTask: Task<Void, Never>?

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest, .query]
        completer.region = Self.defaultSearchRegion
    }

    func locatedResult(for result: LocationSearchResult) async -> LocatedSearchResult? {
        if let coordinate = result.coordinate {
            return LocatedSearchResult(result: result, coordinate: coordinate)
        }

        let primaryRequest: MKLocalSearch.Request
        if let completion = result.completion {
            primaryRequest = MKLocalSearch.Request(completion: completion)
        } else {
            primaryRequest = MKLocalSearch.Request()
            primaryRequest.naturalLanguageQuery = [result.title, result.subtitle]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }
        primaryRequest.resultTypes = [.address, .pointOfInterest]
        primaryRequest.region = Self.defaultSearchRegion

        if let item = await firstMapItem(for: primaryRequest) {
            return locatedResult(from: item, fallback: result)
        }

        guard result.completion != nil else { return nil }

        let fallbackRequest = MKLocalSearch.Request()
        fallbackRequest.naturalLanguageQuery = [result.title, result.subtitle]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        fallbackRequest.resultTypes = [.address, .pointOfInterest]
        fallbackRequest.region = Self.defaultSearchRegion

        guard let item = await firstMapItem(for: fallbackRequest) else {
            return nil
        }
        return locatedResult(from: item, fallback: result)
    }

    private func firstMapItem(for request: MKLocalSearch.Request) async -> MKMapItem? {
        do {
            return try await MKLocalSearch(request: request).start().mapItems.first
        } catch {
            return nil
        }
    }

    private func locatedResult(from item: MKMapItem, fallback result: LocationSearchResult) -> LocatedSearchResult {
        let resolved = LocationSearchResult(
            title: item.name ?? result.title,
            subtitle: item.placemark.title ?? result.subtitle,
            latitude: item.placemark.coordinate.latitude,
            longitude: item.placemark.coordinate.longitude
        )
        return LocatedSearchResult(result: resolved, coordinate: item.placemark.coordinate)
    }

    private func search() {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searchTask?.cancel()
        fallbackTask?.cancel()
        guard !term.isEmpty else {
            results = []
            completer.queryFragment = ""
            return
        }

        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }

            completer.queryFragment = term
            runFallbackSearch(for: term)
        }
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let mapped = completer.results.map { completion in
            LocationSearchResult(
                title: completion.title,
                subtitle: completion.subtitle,
                completion: completion
            )
        }

        guard mapped.isEmpty == false else { return }
        results = Self.sorted(Self.deduplicated(mapped), for: query)
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        runFallbackSearch(for: query.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func runFallbackSearch(for term: String) {
        fallbackTask?.cancel()
        guard !term.isEmpty else { return }

        fallbackTask = Task {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = term
            request.resultTypes = [.address, .pointOfInterest]
            request.region = Self.defaultSearchRegion

            do {
                let response = try await MKLocalSearch(request: request).start()
                guard !Task.isCancelled else { return }
                let mapped = response.mapItems.map { item in
                    LocationSearchResult(
                        title: item.name ?? term,
                        subtitle: item.placemark.title ?? "",
                        latitude: item.placemark.coordinate.latitude,
                        longitude: item.placemark.coordinate.longitude
                    )
                }
                results = Self.sorted(Self.deduplicated(results + mapped), for: term)
            } catch {
                guard !Task.isCancelled else { return }
                if results.isEmpty {
                    results = []
                }
            }
        }
    }

    static let defaultSearchRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780),
        span: MKCoordinateSpan(latitudeDelta: 1.2, longitudeDelta: 1.2)
    )

    private static func deduplicated(_ values: [LocationSearchResult]) -> [LocationSearchResult] {
        var seen = Set<String>()
        return values.filter { seen.insert($0.id).inserted }
    }

    private static func sorted(_ values: [LocationSearchResult], for term: String) -> [LocationSearchResult] {
        let normalizedTerm = normalized(term)
        guard !normalizedTerm.isEmpty else { return values }

        return values.enumerated().sorted { lhs, rhs in
            let lhsScore = relevanceScore(for: lhs.element, term: normalizedTerm)
            let rhsScore = relevanceScore(for: rhs.element, term: normalizedTerm)
            if lhsScore != rhsScore {
                return lhsScore < rhsScore
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    private static func relevanceScore(for result: LocationSearchResult, term: String) -> Int {
        let title = normalized(result.title)
        let subtitle = normalized(result.subtitle)
        let hasCoordinate = result.coordinate != nil

        if title == term { return 0 }
        if title.hasPrefix(term) { return 1 }
        if title.contains(term) { return 2 }
        if subtitle.contains(term) { return 3 }
        if hasCoordinate { return 20 }
        return 40
    }

    private static func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
