import SwiftUI
import MapKit

struct LocationSearchView: View {
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language
    @StateObject private var search = LocationSearchModel()
    @State private var isSearchPresented = false

    var body: some View {
        NavigationStack {
            List(search.results) { result in
                Button {
                    onSelect(result.title)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(result.title)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if !result.subtitle.isEmpty {
                            Text(result.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            }
            .tint(.primary)
            .navigationTitle(L.tr("Location", language: language))
            .searchable(
                text: $search.query,
                isPresented: $isSearchPresented,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: L.tr("Search maps", language: language)
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.tr("Cancel", language: language)) {
                        dismiss()
                    }
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
}

struct LocationSearchResult: Identifiable, Hashable {
    let title: String
    let subtitle: String

    var id: String { "\(title)\n\(subtitle)" }
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
        completer.region = Self.seoulSearchRegion
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
            LocationSearchResult(title: completion.title, subtitle: completion.subtitle)
        }

        guard mapped.isEmpty == false else { return }
        results = Self.deduplicated(mapped)
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
            request.region = Self.seoulSearchRegion

            do {
                let response = try await MKLocalSearch(request: request).start()
                guard !Task.isCancelled else { return }
                let mapped = response.mapItems.map { item in
                    LocationSearchResult(
                        title: item.name ?? term,
                        subtitle: item.placemark.title ?? ""
                    )
                }
                results = Self.deduplicated(results + mapped)
            } catch {
                guard !Task.isCancelled else { return }
                if results.isEmpty {
                    results = []
                }
            }
        }
    }

    private static let seoulSearchRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780),
        span: MKCoordinateSpan(latitudeDelta: 1.2, longitudeDelta: 1.2)
    )

    private static func deduplicated(_ values: [LocationSearchResult]) -> [LocationSearchResult] {
        var seen = Set<String>()
        return values.filter { seen.insert($0.id).inserted }
    }
}
