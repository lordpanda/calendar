# iOS Calendar App — 개발 플랜

## 1. 프로젝트 개요

### 1.1 목표
iOS 26의 기본 캘린더 앱과 동일한 사용자 경험을 제공하되, **날짜를 탭하면 Google Calendar 스타일의 일간 타임테이블이 펼쳐지는** 하이브리드 캘린더 앱을 개발한다.

### 1.2 핵심 차별점
| 항목 | iOS 기본 캘린더 | 본 앱 |
|---|---|---|
| Day 뷰 | 이벤트 리스트 | **시간축 기반 타임테이블** (Google Calendar 방식) |
| 메인 컬러 | 빨강 (Red) | **시스템 블루** (`Color.accentColor` / `.tint`) |
| 동기화 | iCloud 중심 | **iCloud + Google Calendar 동등 연동** |
| 타깃 OS | iOS 17+ | **iOS 26+ 전용** (Liquid Glass 활용) |

### 1.3 기술 스택
- **언어/프레임워크**: Swift 6 + SwiftUI (iOS 26 SDK)
- **로컬 저장소**: SwiftData (이벤트 캐시 + 오프라인)
- **iCloud 연동**: EventKit (EKEventStore, EKCalendar, EKEvent)
- **Google 연동**: Google Calendar API v3 + Google Sign-In SDK
- **인증**: OAuth 2.0 (Google), 시스템 권한 (EventKit)
- **빌드/배포**: Xcode 26, iOS 26 디바이스 대상

---

## 2. 기능 명세

### 2.1 뷰 구성 — Monthly + Day 두 가지만
iOS 기본 캘린더의 compact / stacked / list / year 뷰는 모두 **제거**한다. 본 앱의 뷰는 다음 두 가지뿐이다.

- **Monthly View** (§2.2) — 메인 화면, 항상 진입점
- **Day View** (§2.3) — 날짜 탭 시 펼쳐지는 일간 타임테이블

뷰 전환 버튼, 리스트 토글, 연간 뷰 진입 등은 UI에서 일체 제외. 화면 전환은 오직 "월 ↔ 그 안의 하루" 한 축으로만 일어난다.

### 2.2 Monthly View (메인 화면)
iOS 기본 캘린더의 monthly view와 픽셀 단위로 동일하게 구현 (단, 뷰 전환 컨트롤은 제외).

**상단 영역**
- 좌측: 현재 스크롤 위치의 **연도 라벨** (탭 동작 없음 — 단순 표시. 사용자가 월을 스크롤하면 연도가 따라 바뀜)
- 우측 툴바: **검색**, **햄버거 메뉴** (≡)
  - 햄버거 탭 → 사이드/시트 드로어 (§2.5)
- 모두 **Liquid Glass 캡슐** 스타일

**월 헤더**
- 큰 제목 "May" (large title, 좌측 정렬)
- 요일 라벨 (S M T W T F S, 시작 요일은 설정값 — §2.6)
- (옵션) 좌측에 주 번호 컬럼 — 설정값 (§2.6)

**캘린더 그리드**
- 6주 × 7일 그리드 (이전/다음 달 회색 처리)
- 각 셀: 날짜 숫자 + 최대 3개 이벤트 pill (초과 시 생략)
- 오늘 날짜: 시스템 블루 원형 배경
- 이벤트 pill: 캘린더 색상에 따른 파스텔톤 + 아이콘
- **세로 스크롤** 시 이전/다음 달로 무한 스크롤

**하단 플로팅 바**
- 좌측 캡슐: "Today" (Liquid Glass) — 탭 시 오늘로 스크롤
- 우측 캡슐: **+ 이벤트 추가**
  - 다른 아이콘 없음 (Inbox, 캘린더 목록 토글, 뷰 전환 모두 제외)
  - 탭 시 EventEditView 모달 (§2.4)

### 2.3 Day View (탭 시 펼쳐지는 일간 타임테이블)
**기본 캘린더와 다른 핵심 기능.**

- 트리거: monthly view에서 날짜 셀 탭
- 트랜지션: bottom sheet 또는 zoom transition (iOS 26 `.zoom(...)`)
- 레이아웃:
  - 상단: 선택한 날짜 헤더 + 닫기 버튼
  - 본문: **세로 스크롤 시간축** (00:00 ~ 24:00, 1시간당 60pt 기본)
  - 각 이벤트: 시작/종료 시간에 따라 직사각형 블록으로 배치
  - 겹치는 이벤트: 좌우로 분할 표시
  - 종일 이벤트: 시간축 상단 고정 영역
- 현재 시간: 빨강 가로선 + 우측 시간 라벨 (오늘인 경우만)
- 좌→우 / 우→좌 스와이프: 이전/다음 날로 페이지 전환
- 빈 영역 길게 누르기: 해당 시간에 이벤트 생성

### 2.4 이벤트 CRUD
- **생성**: + 버튼 또는 day view 길게 누르기
  - 제목, 위치, 시작/종료, 종일 토글, 알림, 반복, 메모, 캘린더 선택, URL
  - **캘린더 선택**: 에디터 상단에 **1줄 가로 캘린더 칩 바**가 상시 노출됨. 기본 캘린더가 미리 하이라이트됨. 변경 시 즉시 캐퍼빌리티가 재평가됨 (§4.5)
  - **반복 에디터**: 선택된 캘린더의 provider 캐퍼빌리티에 따라 옵션이 동적으로 노출됨 (지원 안 되는 항목은 숨김)
- **편집**: 이벤트 탭 → 상세 시트 → 편집
- **삭제**: 상세 시트 또는 day view 블록 스와이프
- **반복 이벤트**: 슈퍼셋 모델 + 캘린더별 캐퍼빌리티 게이팅 (§4.4 / §4.5)

### 2.5 햄버거 드로어 (캘린더 목록 + 설정 진입)
상단 우측 햄버거(≡) 탭 시 등장. 시트(half/full) 또는 사이드 드로어 형태 — iPhone에서는 우측에서 슬라이드 인하는 시트, iPad에서는 사이드 드로어.

**구성**
1. **캘린더 목록** (메인 컨텐츠)
   - 계정별 섹션 헤더 (iCloud / Google 계정명)
   - 각 캘린더 행: 컬러 dot + 이름 + 표시/숨김 토글
   - 컬러 dot 탭 시 §2.6의 컬러 변경 시트로 이동 (또는 settings로 점프)
   - 행을 길게 누르면 정렬/숨김 핸들
2. **하단 고정 영역**
   - "**설정**" 진입 행 (gear 아이콘 + 텍스트, 풀 너비 탭) → §2.6 Settings로 push 또는 시트 위 push 네비

**제외** (이전 안에서 제거된 것)
- Inbox 영역 없음
- "기본 캘린더 지정"은 이 화면에서 안 함 → 설정(§2.6)에서 처리

### 2.6 설정 (Settings)
햄버거 드로어 → "설정" 진입.

**계정 / 동기화**
- 연결된 계정 목록 (iCloud, Google×N)
- **"캘린더 추가"** 버튼 → 새 Google 계정 OAuth 흐름 시작 또는 iCloud 권한 재요청
- 계정 제거 (로컬에서 분리 — 원격 데이터는 건드리지 않음)
- 계정별 마지막 동기화 시각 표시 + "지금 동기화" 버튼

**캘린더 외관**
- **Start of the week**: 일/월/토 (또는 시스템 기본) — locale 기본값 fallback
- **Show week numbers**: on/off (켜면 §2.2 좌측에 주 번호 컬럼)
- **기본 캘린더**: 새 이벤트 생성 시 기본으로 선택될 캘린더 한 개 지정
- 일정 표시 밀도(셀당 최대 pill 수) — 향후 확장 여지

**캘린더별 색상**
- 모든 캘린더(iCloud + Google) 리스트
- 행 탭 시 컬러 픽커
- **원본 색상은 절대 건드리지 않음** — 본 앱에서만 적용되는 **로컬 오버라이드**로만 저장
  - 즉, iCloud `EKCalendar.cgColor` 쓰기 / Google Calendar API color 쓰기는 **하지 않음**
  - iOS 시스템 캘린더, 다른 앱, 다른 디바이스의 표시에는 일절 영향 없음
- 이 제약이 없으므로 **iOS 기본 캘린더보다 더 풍부한 팔레트 제공 가능**
  - 큐레이션된 팔레트 30+ 색 (iOS 기본은 ~12색)
  - 커스텀 hex / HSB 입력
  - 다크/라이트 모드별로 별도 색을 지정할 수 있는 advanced 옵션 (선택)
- "원본 색상으로 되돌리기" 한 번 탭으로 오버라이드 해제 — 원본은 항상 보존되어 있음
- 저장 위치: 로컬 SwiftData (`CalendarSource.colorOverrideHex`) — 계정 동기화에는 포함하지 않음 (앱 내부 표시 설정이므로)

**기타**
- 알림 기본값 (이벤트 시작 몇 분 전)
- 앱 정보 / 라이선스

### 2.7 동기화
- **iCloud (EventKit)**:
  - 권한 요청 (Full Access — iOS 17+ 권한 모델)
  - `EKEventStoreChanged` 알림 관찰 → 변경분 반영
- **Google Calendar**:
  - OAuth 2.0 인증 (Google Sign-In)
  - Calendar API v3로 이벤트/캘린더 fetch
  - `syncToken` 기반 증분 동기화
  - Push notification (선택, Pub/Sub) 또는 폴링 (15분)
- **충돌 처리**: 동일 ID 이벤트가 양쪽에 있을 수 없음 (소스별로 분리 저장)

### 2.8 검색
- 상단 검색 버튼 → 전체 화면 검색
- 제목/위치/메모 인덱스 (SwiftData FTS)
- 결과 탭 시 해당 일자 day view 오픈

---

## 3. UI/UX — Liquid Glass 디자인 시스템

### 3.1 iOS 26 Liquid Glass 활용 지점
- 상단 툴바 캡슐: `.glassEffect()` 또는 `.background(.regularMaterial, in: Capsule())`
- 하단 플로팅 바: `.glassEffect(in: Capsule())`
- 시트/모달: `.presentationBackground(.thinMaterial)`
- 캘린더 색상 pill: 반투명 + 블러
- Day view 종일 이벤트 영역: 헤더 stick 시 glass blur

### 3.2 컬러 시스템
- **Accent**: `Color.accentColor` = system blue (`AccentColor` 에셋)
- **Today highlight**: blue circle fill, white text
- **이벤트 pill 배경**: 캘린더 컬러의 알파 0.25 + 동일 컬러 텍스트
- 다크 모드 자동 대응

### 3.3 타이포그래피
- Month title: `.largeTitle.bold()`
- 요일 라벨: `.caption.foregroundStyle(.secondary)`
- 날짜 숫자: `.title3.weight(.medium)`
- 이벤트 pill 텍스트: `.caption2` truncating tail

### 3.4 햅틱 & 애니메이션
- 날짜 탭: light impact
- 이벤트 생성/삭제: success / warning
- 월 전환: spring(response: 0.4, damping: 0.85)
- Day view 등장: matched geometry effect 또는 `.zoom`

---

## 4. 아키텍처

### 4.1 레이어 구조
```
┌────────────────────────────────────────┐
│  Views (SwiftUI)                       │
│   MonthView / DayView / EventEditView  │
├────────────────────────────────────────┤
│  ViewModels (@Observable)              │
│   CalendarViewModel / DayViewModel     │
├────────────────────────────────────────┤
│  Services                              │
│   EventService (CRUD 통합 인터페이스)  │
│   SyncCoordinator (양방향 동기화)      │
├────────────────────────────────────────┤
│  Providers                             │
│   EventKitProvider / GoogleProvider    │
├────────────────────────────────────────┤
│  Storage                               │
│   SwiftData (Event, Calendar, Account) │
└────────────────────────────────────────┘
```

### 4.2 데이터 모델 (SwiftData)
```swift
@Model class CalendarAccount {
    var id: UUID
    var provider: Provider // .iCloud / .google
    var displayName: String
    var calendars: [CalendarSource]
}

@Model class CalendarSource {
    var id: String            // provider 고유 ID
    var account: CalendarAccount
    var title: String
    var colorHex: String           // 원본 (provider 제공) — 절대 수정 안 함
    var colorOverrideHex: String?  // 본 앱에서만 적용되는 로컬 오버라이드 (§2.6)
    var isVisible: Bool
    var events: [Event]
}

@Model class Event {
    var id: String            // provider 고유 ID
    var calendar: CalendarSource
    var title: String
    var location: String?
    var notes: String?
    var startDate: Date
    var endDate: Date
    var startTimeZone: String?     // IANA TZ ID
    var endTimeZone: String?
    var isAllDay: Bool
    var recurrence: RecurrenceSpec?  // ← 양 백엔드 스펙 모두 표현 가능한 슈퍼셋
    var recurrenceExceptions: [EventOverride]  // 수정/삭제된 단일 인스턴스
    var alarms: [Date]
    var lastModified: Date
    var etag: String?         // Google 동기화용
}

// RFC 5545 슈퍼셋 — EventKit + Google 모두를 표현 가능
@Model class RecurrenceSpec {
    var rrules: [String]              // RRULE 들 (Google은 복수 허용, iCloud는 보통 1개)
    var exrules: [String]             // EXRULE (Google deprecated지만 read는 지원)
    var rdates: [Date]                // 명시적 추가 발생
    var exdates: [Date]               // 명시적 제외 발생
    var timeZone: String              // RRULE의 기준 TZ
}

// 반복 인스턴스 단일 수정/삭제 (this-and-future / this-only)
@Model class EventOverride {
    var originalStart: Date           // 원본 인스턴스의 시작 시각
    var isCancelled: Bool
    var override: Event?              // 수정된 경우 대체 이벤트
}
```

### 4.3 Provider 추상화
```swift
protocol CalendarProvider {
    func authenticate() async throws
    func fetchCalendars() async throws -> [CalendarSource]
    func fetchEvents(in range: DateInterval, calendar: CalendarSource) async throws -> [Event]
    func create(_ event: Event) async throws -> Event
    func update(_ event: Event) async throws -> Event
    func delete(_ event: Event) async throws
    func observeChanges() -> AsyncStream<ChangeSet>
}
```
두 구현체: `EventKitProvider`, `GoogleCalendarProvider`.

### 4.4 반복 이벤트 처리 (iCloud + Google 풀 스펙 지원)

내부 표현은 **RFC 5545 슈퍼셋**(`RecurrenceSpec`)으로 통일하고, 각 provider 경계에서 양방향 변환한다. 어느 한쪽 스펙으로 라운드트립할 때 정보 손실이 없어야 한다.

#### 지원 범위
| 항목 | EventKit (`EKRecurrenceRule`) | Google Calendar API | 본 앱 내부 |
|---|---|---|---|
| FREQ (DAILY/WEEKLY/MONTHLY/YEARLY) | ✅ | ✅ | ✅ |
| INTERVAL | ✅ | ✅ | ✅ |
| BYDAY (요일 + 서수) | ✅ (`EKRecurrenceDayOfWeek`) | ✅ | ✅ |
| BYMONTHDAY / BYYEARDAY / BYWEEKNO | ✅ | ✅ | ✅ |
| BYMONTH / BYSETPOS | ✅ | ✅ | ✅ |
| BYHOUR / BYMINUTE / BYSECOND | ❌ (EventKit 미지원) | ✅ | 저장은 하되, iCloud 쓰기 시 경고 |
| WKST | ✅ (`firstDayOfTheWeek`) | ✅ | ✅ |
| COUNT / UNTIL | ✅ (`EKRecurrenceEnd`) | ✅ | ✅ |
| 복수 RRULE | ❌ (1개만) | ✅ | 저장 가능, iCloud 쓰기 시 첫 번째만 + 사용자 경고 |
| EXRULE | ❌ | ✅ (read-only) | read 가능, write는 EXDATE로 변환 |
| RDATE | △ (인스턴스 추가로 우회) | ✅ | ✅ |
| EXDATE | △ (occurrence 삭제로 우회) | ✅ | ✅ |
| 단일 인스턴스 수정 (`recurrenceId`) | ✅ (`EKEvent` per occurrence) | ✅ (`recurringEventId` + `originalStartTime`) | `EventOverride` |
| 무한 반복 | ✅ | ✅ | ✅ (rendering 시 가시 윈도우로 제한) |

#### 변환 레이어
- `RecurrenceCodec`
  - `func encode(_ spec: RecurrenceSpec) -> EKRecurrenceRule?` — EventKit 표현으로 (lossy 경고 포함)
  - `func decode(_ rule: EKRecurrenceRule, tz: TimeZone) -> RecurrenceSpec`
  - `func encode(_ spec: RecurrenceSpec) -> [String]` — Google `recurrence` 배열 (RRULE/EXRULE/RDATE/EXDATE)
  - `func decode(_ recurrence: [String], tz: TimeZone) -> RecurrenceSpec`
- RRULE 문자열 파서/직렬화기: RFC 5545 §3.3.10 100% 구현 (자체 구현 또는 검증된 라이브러리)
- TZID 처리: floating time, UTC, IANA TZ 모두 보존

#### 인스턴스 전개 (Expansion)
- 화면에 보이는 윈도우(예: 보이는 월 ± 1개월)만 전개
- 우선순위: `RDATE` 추가 → `RRULE` 전개 → `EXRULE`/`EXDATE` 제외 → `EventOverride` 적용
- `EventOverride.isCancelled == true` 인스턴스는 비표시
- 무한 반복은 가시 윈도우 + 검색 시점에만 전개

#### 수정 UX (3-way prompt)
사용자가 반복 이벤트를 수정/삭제할 때:
1. "이 이벤트만" → `EventOverride` 생성 (해당 시각 EXDATE + 새 단발 이벤트 OR Google `recurringEventId` 사용)
2. "이 이벤트와 이후 모든" → 원본 RRULE에 `UNTIL` 추가, 새 시점부터 새 RRULE 생성
3. "모든 이벤트" → 마스터 이벤트 자체 업데이트

EventKit과 Google 모두 동일 UX, 내부적으로는 provider별 메서드로 분기.

#### 테스트 매트릭스
RFC 5545 표준 예제(§3.8.5.3, 부록) 30+ 케이스에 대해:
- EventKit ↔ 내부 ↔ Google 라운드트립 무손실 검증
- 타임존 경계 (DST 전후, UTC offset 변경) 케이스
- 무한 반복 + EXDATE 다수 + 단일 수정 복합 케이스

### 4.5 캐퍼빌리티 게이팅 & 캘린더 전환 손실 경고

이벤트 에디터는 **선택된 캘린더의 provider 캐퍼빌리티**에 묶여 동작한다. 동일 에디터 화면이라도 iCloud 캘린더가 선택돼 있으면 BYHOUR/복수 RRULE 같은 옵션이 아예 보이지 않고, Google 캘린더로 바꾸면 펼쳐진다.

#### 캘린더 칩 바 (Picker 대체)
에디터 상단에 가로 1줄짜리 영역으로 **모든 쓰기 가능 캘린더**가 칩 형태로 상시 노출된다. 별도 picker / 모달이 없고, 탭 한 번으로 선택이 바뀐다.

```
┌──────────────────────────────────────────────────────────┐
│  ● 개인  ◉ 업무  ● 가족  ● 운동  ● Birthdays  ● 공휴일 ▶│
└──────────────────────────────────────────────────────────┘
                ↑ 선택됨 (하이라이트)
```

- **레이아웃**: `HStack` 내부에 `ScrollView(.horizontal)` — 캘린더 수가 많으면 가로 스크롤. 화면 양끝에 그라데이션 페이드.
- **칩 모양**: 좌측 캘린더 컬러 dot + 캘린더명. iCloud/Google 구분은 작은 글리프(클라우드/G 아이콘) 또는 미표시(아래 옵션 참조).
- **선택 상태**:
  - 선택: 캡슐 배경이 캘린더 컬러의 알파 0.2 + 컬러 보더 1.5pt + 텍스트 굵게 + light haptic
  - 비선택: 투명 배경 + secondary 텍스트
- **순서**: 사용자가 지정한 기본 캘린더가 맨 앞 → 최근 사용 순 → 나머지 알파벳 순. 화면 진입 시 선택된 칩이 보이도록 스크롤 자동 정렬.
- **읽기 전용 캘린더**(공휴일 등 write 불가)는 칩 자체를 표시하지 않음.
- 계정 여러 개가 같은 색을 쓸 수 있어 dot만으로는 부족 → 텍스트가 always-on.

#### Capability 인터페이스
```swift
struct RecurrenceCapability {
    var allowsByHourMinuteSecond: Bool
    var allowsMultipleRRules: Bool
    var allowsExRule: Bool                // write
    var allowsBySetPos: Bool
    var allowsByWeekNo: Bool
    var allowsByYearDay: Bool
    var allowsRDateExDate: Bool
    var maxAlarms: Int
    // ...추가될 수 있음
}

extension CalendarProvider {
    var recurrenceCapability: RecurrenceCapability { get }
}
```
- `EventKitProvider`: BYHOUR/복수 RRULE/EXRULE write = false, 나머지 true
- `GoogleCalendarProvider`: 거의 모두 true

#### 에디터 동작
1. 칩 탭 → ViewModel이 새 캐퍼빌리티를 받아옴
2. UI: 미지원 옵션 행은 **숨김** (회색 처리가 아니라 제거 — 사용자 혼동 방지)
3. 반복 설정 요약 라벨은 현재 캐퍼빌리티 내에서만 표시 가능한지 다시 평가

#### 캘린더 전환 시 손실 경고 흐름
사용자가 다른 칩을 탭했을 때:

```
[현재 RecurrenceSpec] --diff(newCapability)--> [LossReport]
```

`LossReport`는 어떤 필드가 잘려나갈지 항목화한다 (예: "매시간 반복 규칙", "추가 반복 규칙 2개", "특정 날짜 제외 3건"). 손실이 있으면 confirmation dialog 표시:

```
┌─────────────────────────────────────────┐
│ "회사 미팅" 의 다음 설정은 iCloud 캘린더 │
│ 에서 지원되지 않아 제거됩니다:          │
│                                         │
│   • 매시간 반복 (BYHOUR)                │
│   • 두 번째 반복 규칙                   │
│                                         │
│   [취소]            [변경하고 제거]     │
└─────────────────────────────────────────┘
```

- **취소**: 선택 칩 원래대로 (탭 이전 상태 복원)
- **변경하고 제거**: `RecurrenceSpec`을 새 캐퍼빌리티에 맞춰 정규화(`spec.downgraded(to: capability)`), 그 결과를 에디터에 반영
- 손실이 없으면 경고 없이 즉시 전환 (light haptic만)

#### 정규화 규칙 (`spec.downgraded(to:)`)
- `allowsMultipleRRules == false` → 첫 번째 RRULE만 유지
- `allowsByHourMinuteSecond == false` → 해당 BY 파트 제거 (FREQ는 보존)
- `allowsExRule == false` → EXRULE을 EXDATE 목록으로 전개 (가시 윈도우 + 1년 한도)
- 결과는 항상 **결정적**이어야 함 (같은 입력 → 같은 출력)

#### 저장 시점 한 번 더 검증
provider에 쓰기 직전에도 동일한 정규화/검증을 거쳐, 에디터 UI 우회 경로(예: 자동화)로 인한 손실을 방지한다. 정규화 결과가 입력과 다르면 audit log에 기록.

---

## 5. 개발 단계 (Milestones)

### Phase 0 — 프로젝트 셋업 (1주)
- [ ] Xcode 26 프로젝트 생성, iOS 26 deployment target
- [ ] App Icon, Accent Color 에셋
- [ ] SwiftLint, 빌드 스크립트, CI 골격
- [ ] Info.plist: NSCalendarsFullAccessUsageDescription, OAuth scheme

### Phase 1 — Monthly View 셸 (2주)
- [ ] 6주 그리드 컴포넌트 (이벤트 더미 데이터)
- [ ] 상단 Liquid Glass 캡슐 툴바 (연도 라벨 / 검색 / 햄버거 ≡)
- [ ] 하단 플로팅 캡슐 (Today / +) — Inbox·캘린더 목록·뷰 전환 아이콘 없음
- [ ] 월간 무한 세로 스크롤 (LazyVStack + onAppear), 연도 라벨이 스크롤에 따라 갱신
- [ ] Today 버튼 동작
- [ ] 다크모드 / 동적 폰트 / locale 대응

### Phase 2 — Day View 타임테이블 (2주)
- [ ] 24시간 시간축 컴포넌트 (1시간 60pt)
- [ ] 이벤트 블록 레이아웃 (겹침 분할 알고리즘)
- [ ] 종일 이벤트 sticky 헤더
- [ ] 현재 시간 인디케이터
- [ ] zoom/sheet 트랜지션
- [ ] 좌우 스와이프 페이지 전환

### Phase 3 — 로컬 CRUD + EventKit (2주)
- [ ] SwiftData 스키마 마이그레이션 셋업
- [ ] EventKit 권한 플로우
- [ ] `EventKitProvider` 구현
- [ ] EventEditView (생성/편집/삭제)
- [ ] EKEventStoreChanged 관찰 → SwiftData 반영
- [ ] `RecurrenceCodec` (EventKit ↔ 내부 `RecurrenceSpec`)
- [ ] EventKit 단일 인스턴스 수정/취소 → `EventOverride` 매핑
- [ ] 3-way 수정 prompt UX (이 이벤트만 / 이후 모두 / 전체)
- [ ] `RecurrenceCapability` 정의 + `EventKitProvider.recurrenceCapability`
- [ ] EventEditView 캘린더 칩 바 (1행 가로 스크롤, 선택 하이라이트) + 캐퍼빌리티 기반 옵션 동적 노출

### Phase 4 — Google Calendar 연동 (2주)
- [ ] Google Sign-In SDK 통합
- [ ] OAuth 토큰 키체인 저장
- [ ] `GoogleCalendarProvider`: 캘린더 / 이벤트 fetch
- [ ] syncToken 증분 동기화
- [ ] 이벤트 양방향 쓰기 (create/update/delete)
- [ ] `RecurrenceCodec` Google 측 (`[String]` ↔ 내부 `RecurrenceSpec`)
- [ ] Google `recurringEventId` + `originalStartTime` → `EventOverride` 매핑
- [ ] RFC 5545 풀 RRULE 파서/직렬화기 + 테스트 매트릭스
- [ ] `GoogleCalendarProvider.recurrenceCapability` + 캘린더 전환 손실 경고 다이얼로그
- [ ] `RecurrenceSpec.downgraded(to:)` 정규화 + 저장 시점 재검증
- [ ] 백그라운드 동기화 (BGAppRefreshTask)

### Phase 5 — 통합 & 폴리시 (2주)
- [ ] 햄버거 드로어 (계정별 캘린더 목록 + 표시/숨김 토글 + 정렬)
- [ ] 설정 화면 (계정 추가/제거, start of week, week numbers, 기본 캘린더, 캘린더별 색상 오버라이드, 알림 기본값)
- [ ] 로컬 컬러 오버라이드 (`colorOverrideHex`) + 큐레이션 팔레트 + hex/HSB 픽커. 원본 색상 쓰기 경로는 의도적으로 미구현
- [ ] 검색 화면 + SwiftData FTS
- [ ] 햅틱 / 트랜지션 최종 튜닝
- [ ] Liquid Glass 효과 점검 (실기기)

### Phase 6 — QA & 베타 (1주)
- [ ] 단위 테스트: 그리드 계산, 겹침 알고리즘, RRULE, syncToken
- [ ] UI 테스트: 핵심 플로우 (이벤트 생성/편집/삭제, 동기화)
- [ ] 실기기 테스트 (iPhone 17 Pro / iPad)
- [ ] TestFlight 베타 배포

**전체 예상 기간**: 약 **12주** (3개월)

---

## 6. 주요 기술 리스크 & 대응

| 리스크 | 영향 | 대응 |
|---|---|---|
| iOS 26 Liquid Glass API 변경 | 디자인 흔들림 | 추상화 레이어 + fallback `.regularMaterial` |
| Google API rate limit | 동기화 지연 | exponential backoff + syncToken 우선 |
| iCloud/Google 동일 이벤트 중복 | 데이터 혼란 | source별 namespace 분리, 병합 UX 없음 |
| 종일/타임존 처리 버그 | 사용자 신뢰 손상 | Date 대신 Calendar/TimeZone 명시적 사용, 전용 테스트 |
| EventKit Full Access 권한 거부 | 핵심 기능 불가 | 권한 거부 시 Google-only 모드 폴백 |
| EventKit ↔ Google 반복 스펙 비대칭 (BYHOUR, 복수 RRULE 등) | 데이터 손실 / 불일치 | 내부는 RFC 5545 슈퍼셋으로 통일, provider 경계에서만 변환. iCloud 쓰기 시 lossy 케이스는 사용자에게 경고 (§4.4) |
| 반복 이벤트 단일 인스턴스 수정/예외 | 동기화 충돌 | `EventOverride` 모델로 통합, 3-way prompt UX |
| 타임존/DST 경계의 반복 전개 오류 | 시간 어긋남 | RRULE 기준 TZID 보존 + DST 전후 전용 테스트 케이스 |

---

## 7. 다음 단계
1. 본 플랜 리뷰 & 우선순위 확정
2. Xcode 프로젝트 생성 + Phase 0 착수
3. 디자인 토큰 (컬러, 간격, 폰트) 정의 후 Phase 1 시작

> 진행하면서 `tasks.md`로 세부 작업을 분해하고, `context.md`로 의사결정 로그를 누적할 예정.
