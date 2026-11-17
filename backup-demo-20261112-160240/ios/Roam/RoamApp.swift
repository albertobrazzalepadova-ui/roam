import SwiftUI
import MapKit
import PhotosUI
import CoreLocation
import UIKit
import CryptoKit


enum RoamStyle {
    static let canvas = Color(red: 0.985, green: 0.982, blue: 0.978)
    static let red = Color(red: 0.88, green: 0.10, blue: 0.19)
    static let surface = Color(red: 0.97, green: 0.97, blue: 0.98)
}
// A single continuous route, forming an R and a compass arrow.
struct RoamMark: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { .init(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height) }
        p.move(to: point(0.26, 0.80)); p.addLine(to: point(0.26, 0.23))
        p.addLine(to: point(0.52, 0.23))
        p.addCurve(to: point(0.52, 0.55), control1: point(0.83, 0.23), control2: point(0.83, 0.55))
        p.addLine(to: point(0.26, 0.55)); p.move(to: point(0.48, 0.55)); p.addLine(to: point(0.76, 0.80))
        p.move(to: point(0.59, 0.79)); p.addLine(to: point(0.76, 0.80)); p.addLine(to: point(0.74, 0.63))
        return p
    }
}
// Secondary pages use quiet native navigation chrome.
struct RoamHeader: ViewModifier {
    func body(content: Content) -> some View {
        content
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.regularMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
    }
}
extension View { func roamHeader() -> some View { modifier(RoamHeader()) } }
struct DiscoveryArtwork: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var tilt: CGSize = .zero
    var body: some View {
        GeometryReader { g in
            ZStack {
                LinearGradient(colors: [Color(red: 1, green: 0.96, blue: 0.94), .white, Color(red: 0.98, green: 0.88, blue: 0.87)], startPoint: .topLeading, endPoint: .bottomTrailing)
                // Street grid gives depth without pretending to be a real map.
                ForEach(0..<7) { index in
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.white.opacity(0.85))
                        .frame(width: 62, height: 120)
                        .rotationEffect(.degrees(-32))
                        .offset(x: CGFloat(index - 3) * 72, y: index.isMultiple(of: 2) ? -28 : 36)
                }
                route(g.size).stroke(RoamStyle.red.opacity(0.12), style: StrokeStyle(lineWidth: 16, lineCap: .round))
                route(g.size).trim(from: 0, to: appeared ? 1 : 0)
                    .stroke(RoamStyle.red, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [4, 7]))
                Circle().stroke(RoamStyle.red.opacity(appeared ? 0 : 0.25), lineWidth: 1)
                    .frame(width: 72).scaleEffect(reduceMotion ? 1 : appeared ? 1.8 : 0.8).offset(x: 45, y: -10)
                ZStack {
                    Circle().fill(.white).frame(width: 62).shadow(color: RoamStyle.red.opacity(0.2), radius: 18, y: 9)
                    Image(systemName: "location.north.fill").font(.system(size: 25, weight: .semibold)).foregroundStyle(RoamStyle.red).rotationEffect(.degrees(30))
                }.offset(x: 45, y: -10).offset(y: reduceMotion ? 0 : appeared ? -5 : 3)
                VStack(alignment: .leading) {
                    Label("IL TUO PROSSIMO WOW", systemImage: "sparkle").font(.system(size: 9, weight: .heavy)).tracking(1.5).padding(10).background(.white.opacity(0.85), in: Capsule())
                    Spacer()
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 4) { Text("Lasciati sorprendere.").font(.system(size: 21, weight: .bold)).tracking(-0.7); Text("La scoperta inizia da te.").font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.headline).foregroundStyle(.white).frame(width: 38, height: 38).background(RoamStyle.red, in: Circle())
                    }
                }.padding(20)
            }
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .overlay(RoundedRectangle(cornerRadius: 28).stroke(.white.opacity(0.9), lineWidth: 1))
            .rotation3DEffect(.degrees(reduceMotion ? 0 : Double(-tilt.height / 25)), axis: (x: 1, y: 0, z: 0))
            .rotation3DEffect(.degrees(reduceMotion ? 0 : Double(tilt.width / 25)), axis: (x: 0, y: 1, z: 0))
            .simultaneousGesture(DragGesture(minimumDistance: 8).onChanged { tilt = CGSize(width: min(80, max(-80, $0.translation.width)), height: min(80, max(-80, $0.translation.height))) }.onEnded { _ in withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) { tilt = .zero } })
            .onAppear {
                if reduceMotion { appeared = true }
                else { withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) { appeared = true } }
            }
        }.frame(height: 214)
        .shadow(color: RoamStyle.red.opacity(0.09), radius: 20, y: 10)
        .accessibilityElement(children: .ignore).accessibilityLabel("Lasciati sorprendere. La scoperta inizia da te.")
    }
    private func route(_ size: CGSize) -> Path {
        Path { p in
            p.move(to: .init(x: -20, y: size.height * 0.6))
            p.addCurve(to: .init(x: size.width * 0.5 + 45, y: size.height * 0.5 - 10), control1: .init(x: size.width * 0.25, y: -20), control2: .init(x: size.width * 0.35, y: size.height * 0.8))
        }
    }
}
struct Place: Codable, Identifiable {
    let id, name, category: String
    let latitude, longitude: Double
    let description, symbol: String
    let distance: Double
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}
struct WebPhoto: Decodable { let url, source_url, author, license, title: String; let provider: String? }
struct WebPhotoResponse: Decodable { let photo: WebPhoto?; let photos: [WebPhoto]? }
struct PlaceActivity: Decodable { let comments: Int; let rating: Double?; let photo: String? }
struct Review: Codable, Identifiable {
    let id, author, body: String
    let rating: Int
}
struct SocialPost: Decodable, Identifiable {
    let id, place_id, author, body, created_at: String
    let rating: Int
    var comments: Int
    let photo: String?
    var saved: Bool
    let mine: Bool
    let place: Place
}
struct SocialFeedResponse: Decodable { let posts: [SocialPost]; let has_more: Bool }
struct SocialComment: Decodable, Identifiable { let id, author, body, created_at: String }
struct SavedResponse: Decodable { let saved: Bool }
struct Profile: Codable { var name = "Viaggiatore"; var bio = "Il prossimo viaggio inizia qui."; var photo: String? }
struct Stats: Codable {
    var comments = 0, posts = 0, places = 0, saved = 0
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        comments = try c.decodeIfPresent(Int.self, forKey: .comments) ?? 0
        posts = try c.decodeIfPresent(Int.self, forKey: .posts) ?? 0
        places = try c.decodeIfPresent(Int.self, forKey: .places) ?? 0
        saved = try c.decodeIfPresent(Int.self, forKey: .saved) ?? 0
    }
}
struct Person: Decodable, Identifiable, Hashable {
    let name: String
    let posts, places: Int
    let mine: Bool
    let photo: String?
    var id: String { name }
}
struct ChatReply: Codable { let reply: String }
struct WeatherResponse: Decodable { let current: Current; struct Current: Decodable { let temperature_2m: Double; let weather_code: Int } }
struct Message: Identifiable { let id = UUID(); let text: String; let user: Bool }

@MainActor final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var coordinate: CLLocationCoordinate2D?
    @Published var city = "La tua zona"
    @Published var status = "Attiva la posizione"
    @Published var permissionDenied = false
    @Published var weather = "Meteo in attesa della posizione"
    func refreshWeather() async {
        guard let c = coordinate else { weather = "Meteo in attesa della posizione"; return }
        guard let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(c.latitude)&longitude=\(c.longitude)&current=temperature_2m,weather_code") else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let current = try JSONDecoder().decode(WeatherResponse.self, from: data).current
            let condition = current.weather_code == 0 ? "Sereno" : current.weather_code <= 3 ? "Nuvoloso" : current.weather_code <= 48 ? "Nebbia" : current.weather_code >= 95 ? "Temporali" : "Precipitazioni"
            weather = "\(Int(current.temperature_2m.rounded()))° · \(condition)"
        } catch { weather = "Meteo non disponibile" }
    }
    override init() { super.init(); manager.delegate = self; manager.desiredAccuracy = kCLLocationAccuracyHundredMeters }
    func request() {
        guard CLLocationManager.locationServicesEnabled() else { status = "Abilita Localizzazione nelle Impostazioni"; permissionDenied = true; return }
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways: status = "Cerco la tua posizione…"; permissionDenied = false; manager.requestLocation()
        case .denied, .restricted: status = "Consenti la posizione nelle Impostazioni"; permissionDenied = true
        @unknown default: break
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways { manager.requestLocation() }
        else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted { status = "Consenti la posizione nelle Impostazioni"; permissionDenied = true; coordinate = nil; city = "La tua zona"; weather = "Meteo in attesa della posizione" }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, location.horizontalAccuracy >= 0, abs(location.timestamp.timeIntervalSinceNow) < 120 else { return }
        coordinate = location.coordinate; status = "Posizione attuale"
        Task { await refreshWeather() }
        CLGeocoder().reverseGeocodeLocation(location) { marks, _ in
            Task { @MainActor in self.city = marks?.first?.locality ?? "Vicino a te" }
        }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { status = "Posizione non disponibile. Riprova all’aperto." }
}

@MainActor final class Store: ObservableObject {
    @Published var places: [Place] = []
    @Published var mapAreaPlaces: [Place]?
    @Published var socialPosts: [SocialPost] = []
    @Published var socialLoading = false
    @Published var socialError: String?
    @Published var socialHasMore = false
    @Published var myPosts: [SocialPost] = []
    @Published var myPostsLoaded = false
    @Published var myPostsError: String?
    @Published var personFeed: [SocialPost] = []
    private var socialRequestID = UUID()
    @Published var webPhotos: [String: WebPhoto] = [:]
    private var webPhotoChecked = Set<String>()
    private var photoAlternatives: [String: [WebPhoto]] = [:]
    @Published var activity: [String: PlaceActivity] = [:]
    @Published var profile = Profile()
    @Published var stats = Stats()
    @Published var error: String?
    @Published var loading = false
    private var placesRequestID = UUID()
    @Published var placesError: String?
    @Published var accountError: String?
    @Published var source = "OpenStreetMap"
    @AppStorage("appleSearchEnabled") var appleSearchEnabled = false
    @AppStorage("viewportSearchEnabled") var viewportSearchEnabled = true
    @AppStorage("apiURL") var apiURL = "http://100.90.158.14:8000"
    func request<T: Decodable>(_ path: String, method: String = "GET", body: Data? = nil) async throws -> T {
        guard let url = URL(string: apiURL + path), ["http", "https"].contains(url.scheme ?? "") else { throw URLError(.badURL) }
        var request = URLRequest(url: url); request.httpMethod = method; request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.timeoutInterval = 65
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String
            throw NSError(domain: "API", code: (response as? HTTPURLResponse)?.statusCode ?? 0, userInfo: [NSLocalizedDescriptionKey: detail ?? "Server non disponibile. Controlla la connessione."])
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
    func load(_ coordinate: CLLocationCoordinate2D?) async {
        async let account: () = loadAccount()
        await loadPlaces(coordinate)
        await account
    }
    private func loadAccount() async {
        do {
            profile = try await request("/profile")
            stats = try await request("/stats")
            accountError = nil
        } catch { if !Task.isCancelled { accountError = "Profilo non sincronizzato. Controlla Tailscale e il backend." } }
    }
    func loadPlaces(_ coordinate: CLLocationCoordinate2D?) async {
        let requestID = UUID(); placesRequestID = requestID
        loading = true; placesError = nil
        defer { if placesRequestID == requestID { loading = false } }
        guard let c = coordinate else { places = []; return }
        do {
            if appleSearchEnabled {
                let (loaded, partial) = try await searchApple(c) { updated in
                    guard self.placesRequestID == requestID else { return }
                    self.places = updated; self.source = "Mappe Apple"
                }
                guard placesRequestID == requestID else { return }
                places = loaded; source = "Mappe Apple"
                if partial { placesError = "Alcune categorie non sono disponibili. Puoi riprovare." }
            }
            else {
                source = "OpenStreetMap"
                let loaded: [Place] = try await request("/places?latitude=\(c.latitude)&longitude=\(c.longitude)")
                try Task.checkCancellation()
                guard placesRequestID == requestID else { return }
                places = loaded
            }
        } catch {
            if !Task.isCancelled && placesRequestID == requestID {
                placesError = appleSearchEnabled ? "Mappe Apple non risponde. Controlla Internet e riprova." : "OpenStreetMap non è disponibile. Riprova o cerca con Mappe Apple."
            }
        }
    }
    private let discoveryQueries: [(String, String, String)] = [
        ("attrazioni turistiche", "Attrazione", "building.columns.fill"),
        ("musei", "Attrazione", "building.columns.fill"),
        ("parchi e giardini", "Parco", "leaf.fill"),
        ("ristoranti", "Ristorante", "fork.knife"),
        ("caffè", "Caffè", "cup.and.saucer.fill"),
        ("negozi", "Negozio", "bag.fill"),
        ("monumenti e siti storici", "Attrazione", "building.columns.fill"),
        ("punti panoramici", "Attrazione", "building.columns.fill"),
        ("gallerie d’arte", "Attrazione", "building.columns.fill"),
        ("pizzerie", "Ristorante", "fork.knife"),
        ("gelaterie e pasticcerie", "Caffè", "cup.and.saucer.fill"),
        ("librerie e mercati", "Negozio", "bag.fill")
    ]
    private func searchApple(_ coordinate: CLLocationCoordinate2D, onUpdate: ([Place]) -> Void) async throws -> ([Place], Bool) {
        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        var results: [String: Place] = [:]
        var lastError: Error?
        for (query, category, symbol) in discoveryQueries {
            try Task.checkCancellation()
            let req = MKLocalSearch.Request()
            req.naturalLanguageQuery = query
            req.resultTypes = .pointOfInterest
            req.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 10000, longitudinalMeters: 10000)
            do {
                let response = try await MKLocalSearch(request: req).start()
                for item in response.mapItems {
                    guard let name = item.name, let location = item.placemark.location else { continue }
                    let distance = origin.distance(from: location) / 1000
                    guard distance <= 5 else { continue }
                    let c = location.coordinate
                    let identity = "\(name.lowercased())|\(String(format: "%.5f", locale: Locale(identifier: "en_US_POSIX"), c.latitude))|\(String(format: "%.5f", locale: Locale(identifier: "en_US_POSIX"), c.longitude))"
                    let id = "apple-" + SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
                    if results[id] == nil {
                        let address = [item.placemark.thoroughfare, item.placemark.subThoroughfare, item.placemark.locality].compactMap { $0 }.joined(separator: " ")
                        results[id] = Place(id: id, name: name, category: category, latitude: c.latitude, longitude: c.longitude, description: address.isEmpty ? "Luogo trovato con Mappe Apple. Verifica gli orari prima di partire." : address, symbol: symbol, distance: distance)
                    }
                }
                try Task.checkCancellation()
                onUpdate(results.values.sorted { $0.distance < $1.distance })
            } catch { try Task.checkCancellation(); lastError = error }
        }
        try Task.checkCancellation()
        if results.isEmpty, let lastError { throw lastError }
        return (results.values.sorted { $0.distance < $1.distance }, lastError != nil)
    }
    func register(_ place: Place) async throws {
        if place.id.hasPrefix("apple-") || place.id.hasPrefix("landmark-") {
            let _: Place = try await request("/places/register", method: "POST", body: JSONEncoder().encode(place))
        }
    }
    func loadWebPhoto(_ place: Place) async {
        guard !webPhotoChecked.contains(place.id) else { return }
        webPhotoChecked.insert(place.id)
        do {
            try await register(place)
            let result: WebPhotoResponse = try await request("/places/\(place.id)/web-image")
            if let photo = result.photo {
                webPhotos[place.id] = photo
                photoAlternatives[place.id] = (result.photos ?? []).filter { $0.url != photo.url }
            }
        } catch { webPhotoChecked.remove(place.id) }
    }
    func nextWebPhoto(_ place: Place) -> Bool {
        guard var alternatives = photoAlternatives[place.id], !alternatives.isEmpty else { return false }
        webPhotos[place.id] = alternatives.removeFirst()
        photoAlternatives[place.id] = alternatives
        return true
    }
    func searchViewport(_ region: MKCoordinateRegion, origin: CLLocationCoordinate2D, onUpdate: (([Place]) -> Void)? = nil) async throws -> [Place] {
        guard viewportSearchEnabled else { return [] }
        let originLocation=CLLocation(latitude:origin.latitude,longitude:origin.longitude)
        let span=MKCoordinateSpan(latitudeDelta:min(2,max(0.01,region.span.latitudeDelta)),longitudeDelta:min(3,max(0.01,region.span.longitudeDelta)))
        let wide=span.latitudeDelta > 0.08 || span.longitudeDelta > 0.12
        let offsets: [(Double,Double)] = wide ? [(-0.25,-0.25),(-0.25,0.25),(0.25,-0.25),(0.25,0.25)] : [(0,0)]
        var results:[String:Place]=[:]
        var failures=0
        for offset in offsets {
            for (query,category,symbol) in (wide ? Array(discoveryQueries.prefix(6)) : discoveryQueries) {
                try Task.checkCancellation()
                let req=MKLocalSearch.Request();req.naturalLanguageQuery=query;req.resultTypes = .pointOfInterest
                req.region=MKCoordinateRegion(center:CLLocationCoordinate2D(latitude:max(-85,min(85,region.center.latitude+span.latitudeDelta*offset.0)),longitude:wrapLongitude(region.center.longitude+span.longitudeDelta*offset.1)),span:MKCoordinateSpan(latitudeDelta:span.latitudeDelta/(wide ? 2 : 1),longitudeDelta:span.longitudeDelta/(wide ? 2 : 1)))
                let search=MKLocalSearch(request:req)
                do {
                    let response = try await withTaskCancellationHandler { try await search.start() } onCancel: { Task { @MainActor in search.cancel() } }
                    for item in response.mapItems {
                        guard let name=item.name,let location=item.placemark.location else { continue }
                        let c=location.coordinate
                        let lonDelta=abs(wrapLongitude(c.longitude-region.center.longitude))
                        guard abs(c.latitude-region.center.latitude)<=region.span.latitudeDelta/2,lonDelta<=region.span.longitudeDelta/2 else { continue }
                        let identity="\(name.lowercased())|\(String(format:"%.5f",locale:Locale(identifier:"en_US_POSIX"),c.latitude))|\(String(format:"%.5f",locale:Locale(identifier:"en_US_POSIX"),c.longitude))"
                        let id="apple-"+SHA256.hash(data:Data(identity.utf8)).map { String(format:"%02x",$0) }.joined()
                        let address=[item.placemark.thoroughfare,item.placemark.locality].compactMap{$0}.joined(separator:" ")
                        if results[id] == nil { results[id]=Place(id:id,name:name,category:category,latitude:c.latitude,longitude:c.longitude,description:address.isEmpty ? "Luogo trovato con Mappe Apple." : address,symbol:symbol,distance:originLocation.distance(from:location)/1000) }
                    }
                    try Task.checkCancellation()
                    onUpdate?(Array(results.values))
                } catch { try Task.checkCancellation(); failures += 1 }
            }
        }
        if results.isEmpty && failures>0 { throw URLError(.cannotLoadFromNetwork) }
        try Task.checkCancellation()
        if places.isEmpty && originLocation.distance(from:CLLocation(latitude:region.center.latitude,longitude:region.center.longitude)) < 5000 {
            places=results.values.filter{$0.distance <= 5}.sorted{$0.distance < $1.distance}
            if !places.isEmpty { source="Mappe Apple" }
        }
        return Array(results.values)
    }
    func loadSocialFeed(ids: [String], savedOnly: Bool, append: Bool = false) async {
        let token = UUID(); socialRequestID = token
        socialLoading = true; socialError = nil
        let offset = append ? (savedOnly ? socialPosts.filter { $0.saved }.count : socialPosts.count) : 0
        if !append {
            let requested = Set(ids.prefix(500))
            socialPosts = socialPosts.filter { savedOnly ? $0.saved : requested.contains($0.place_id) }
            socialHasMore = false
        }
        defer { if socialRequestID == token { socialLoading = false } }
        do {
            let payload = try JSONSerialization.data(withJSONObject: ["place_ids": Array(ids.prefix(500)), "saved_only": savedOnly, "offset": offset])
            let result: SocialFeedResponse = try await request("/feed/query", method: "POST", body: payload)
            try Task.checkCancellation()
            guard token == socialRequestID else { return }
            socialPosts = append ? socialPosts + result.posts : result.posts
            socialHasMore = result.has_more
        } catch { if !Task.isCancelled && token == socialRequestID { socialError = "Feed non sincronizzato. Controlla la connessione e riprova." } }
    }
    func toggleSaved(_ post: SocialPost) async {
        do {
            let payload = try JSONSerialization.data(withJSONObject: ["saved": !post.saved])
            let result: SavedResponse = try await request("/feed/posts/\(post.id)/saved", method: "PUT", body: payload)
            if result.saved != post.saved { stats.saved = max(0, stats.saved + (result.saved ? 1 : -1)) }
            updatePost(post.id) { $0.saved = result.saved }
        } catch { self.error = "Salvataggio non riuscito. Riprova." }
    }
    // Feed and profile hold separate copies of the same post; keep both in sync.
    func updatePost(_ id: String, _ change: (inout SocialPost) -> Void) {
        if let index = socialPosts.firstIndex(where: { $0.id == id }) { change(&socialPosts[index]) }
        if let index = myPosts.firstIndex(where: { $0.id == id }) { change(&myPosts[index]) }
        if let index = personFeed.firstIndex(where: { $0.id == id }) { change(&personFeed[index]) }
    }
    // Places a post can be tied to: nearby results plus the last explored map area.
    var knownPlaces: [Place] {
        var seen = Set<String>()
        return (places + (mapAreaPlaces ?? [])).filter { seen.insert($0.id).inserted }.sorted { $0.distance < $1.distance }
    }
    func loadMyPosts() async {
        do {
            let result: SocialFeedResponse = try await request("/feed/mine")
            myPosts = result.posts; myPostsLoaded = true; myPostsError = nil
        } catch { if !Task.isCancelled { myPostsError = "I tuoi post non sono sincronizzati. Riprova." } }
    }
    func published(_ post: SocialPost) {
        myPosts.insert(post, at: 0); stats.posts += 1
    }
    func deletePost(_ post: SocialPost) async -> Bool {
        do {
            guard let url = URL(string: apiURL + "/feed/posts/" + post.id) else { throw URLError(.badURL) }
            var req = URLRequest(url: url); req.httpMethod = "DELETE"
            let (_, response) = try await URLSession.shared.data(for: req)
            guard (response as? HTTPURLResponse)?.statusCode == 204 else { throw URLError(.badServerResponse) }
            socialPosts.removeAll { $0.id == post.id }; myPosts.removeAll { $0.id == post.id }; personFeed.removeAll { $0.id == post.id }
            stats.posts = max(0, stats.posts - 1)
            return true
        } catch { self.error = "Eliminazione non riuscita. Riprova."; return false }
    }
    private func wrapLongitude(_ value: Double) -> Double { let v=(value+180).truncatingRemainder(dividingBy:360);return (v<0 ? v+360 : v)-180 }
    func refreshActivity(_ place: Place) async {
        do {
            try await register(place)
            let value: PlaceActivity = try await request("/places/\(place.id)/activity")
            activity[place.id] = value
        } catch { }
    }
    private func encoded(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=?#"))) ?? ""
    }
    func searchPeople(_ query: String) async throws -> [Person] { try await request("/people?q=" + encoded(query)) }
    // Free-text Apple Maps search used by Cerca; only runs when the user opted in to Apple search.
    func searchPlaces(_ query: String, near coordinate: CLLocationCoordinate2D, category fallback: String? = nil) async throws -> [Place] {
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = query
        req.resultTypes = .pointOfInterest
        req.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 20000, longitudinalMeters: 20000)
        let search = MKLocalSearch(request: req)
        let response = try await withTaskCancellationHandler { try await search.start() } onCancel: { Task { @MainActor in search.cancel() } }
        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return response.mapItems.compactMap { item -> Place? in
            guard let name = item.name, let location = item.placemark.location else { return nil }
            let c = location.coordinate
            let identity = "\(name.lowercased())|\(String(format: "%.5f", locale: Locale(identifier: "en_US_POSIX"), c.latitude))|\(String(format: "%.5f", locale: Locale(identifier: "en_US_POSIX"), c.longitude))"
            let id = "apple-" + SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
            let category: String
            switch item.pointOfInterestCategory {
            case .some(.park), .some(.nationalPark), .some(.beach): category = "Parco"
            case .some(.restaurant), .some(.foodMarket), .some(.winery), .some(.brewery): category = "Ristorante"
            case .some(.cafe), .some(.bakery): category = "Caffè"
            case .some(.store): category = "Negozio"
            case .some(.museum), .some(.theater), .some(.library), .some(.university): category = "Attrazione"
            default: category = fallback ?? "Attrazione"
            }
            let symbol = ["Parco": "leaf.fill", "Ristorante": "fork.knife", "Caffè": "cup.and.saucer.fill", "Negozio": "bag.fill"][category] ?? "building.columns.fill"
            let address = [item.placemark.thoroughfare, item.placemark.subThoroughfare, item.placemark.locality].compactMap { $0 }.joined(separator: " ")
            return Place(id: id, name: name, category: category, latitude: c.latitude, longitude: c.longitude, description: address.isEmpty ? "Luogo trovato con Mappe Apple." : address, symbol: symbol, distance: origin.distance(from: location) / 1000)
        }.sorted { $0.distance < $1.distance }
    }
    func loadPersonFeed(_ name: String) async throws {
        let result: SocialFeedResponse = try await request("/people/posts?name=" + encoded(name))
        personFeed = result.posts
    }
}

@main struct RoamApp: App {
    @StateObject private var store = Store()
    @StateObject private var location = LocationService()
    init() {
        // One light native appearance for standard, scroll-edge and compact navigation.
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundColor = .systemBackground
        appearance.shadowColor = .clear
        appearance.titleTextAttributes = [
            .foregroundColor: UIColor.label,
            .font: UIFont.preferredFont(forTextStyle: .headline)
        ]
        let navigationBar = UINavigationBar.appearance()
        navigationBar.standardAppearance = appearance
        navigationBar.scrollEdgeAppearance = appearance
        navigationBar.compactAppearance = appearance
        navigationBar.compactScrollEdgeAppearance = appearance
        navigationBar.tintColor = UIColor(RoamStyle.red)
        navigationBar.prefersLargeTitles = false
    }
    var body: some Scene { WindowGroup { RootView().environmentObject(store).environmentObject(location).tint(RoamStyle.red).preferredColorScheme(.light) } }
}
struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var store: Store
    @EnvironmentObject var location: LocationService
    var body: some View {
        TabView {
            SocialFeedView().tabItem { Label("Feed", systemImage: "rectangle.stack.fill") }
            SearchView().tabItem { Label("Cerca", systemImage: "magnifyingglass") }
            HomeView().tabItem { Label("Mappa", systemImage: "map") }
            ChatView().tabItem { Label("Assistente", systemImage: "bubble.left.and.bubble.right") }
            ProfileView().tabItem { Label("Profilo", systemImage: "person.crop.circle") }
        }
        .task { location.request() }
        .task(id: location.coordinate.map { "\($0.latitude),\($0.longitude)" } ?? "no-location") { await store.load(location.coordinate) }
        .onChange(of: scenePhase) { _, phase in if phase == .active { location.request() } }
        .alert("Qualcosa non ha funzionato", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: { Text(store.error ?? "") }
    }
}
struct Avatar: View {
    let photo: String?
    var size: CGFloat = 52
    var body: some View {
        Group {
            if let photo, let data = Data(base64Encoded: photo), let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFill() }
            else { Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(RoamStyle.red.opacity(0.7)) }
        }.frame(width: size, height: size).clipShape(Circle())
    }
}
struct PlaceSheet: View {
    let place: Place
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            PlaceView(place: place)
                .toolbar { ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") { dismiss() }.foregroundStyle(RoamStyle.red)
                } }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
    }
}
struct PlaceGlyph: View {
    let category: String
    var body: some View {
        if category == "Parco" || category == "Ristorante" {
            Image(systemName: category == "Parco" ? "leaf.fill" : "fork.knife").resizable().scaledToFit()
        } else {
        Image(category == "Caffè" ? "RoamCafe" : category == "Negozio" ? "RoamShop" : "RoamAttraction")
            .resizable().scaledToFit().accessibilityHidden(true)
        }
    }
}
struct RoamMapPin: View {
    let place: Place
    var selected = false
    var body: some View {
        VStack(spacing: -2) {
            PlaceGlyph(category: place.category)
                .frame(width: 21, height: 21).padding(10)
                .foregroundStyle(selected ? .white : RoamStyle.red)
                .background(selected ? RoamStyle.red : .white, in: Circle())
                .overlay(Circle().stroke(selected ? .white : RoamStyle.red, lineWidth: 2))
            TrianglePointer().fill(selected ? RoamStyle.red : .white).frame(width: 12, height: 8)
        }
        .shadow(color: .black.opacity(0.16), radius: 6, y: 3)
        .scaleEffect(selected ? 1.12 : 1)
        .accessibilityLabel("\(place.name), \(place.category)")
    }
}
struct TrianglePointer: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in p.move(to: .zero); p.addLine(to: .init(x: rect.maxX, y: 0)); p.addLine(to: .init(x: rect.midX, y: rect.maxY)); p.closeSubpath() }
    }
}
struct MapGlassButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 16, weight: .semibold))
            .foregroundStyle(RoamStyle.red).frame(width: 46, height: 46)
            .background(.regularMaterial, in: Circle())
            .overlay(Circle().stroke(.white.opacity(0.65), lineWidth: 1))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.9 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.25), value: configuration.isPressed)
    }
}
struct MapPlaceGroup: Identifiable {
    let id:String
    let places:[Place]
    var coordinate:CLLocationCoordinate2D { .init(latitude:places[0].latitude,longitude:places[0].longitude) }
}
struct ExploreMap: View {
    let places: [Place]
    let coordinate: CLLocationCoordinate2D
    var compact = false
    var categoryFilter = "Tutti"
    var searchQuery = ""
    @EnvironmentObject private var store: Store
    @State private var viewportPlaces: [Place] = []
    @State private var viewportKey = ""
    @State private var queryRegion: MKCoordinateRegion?
    @State private var viewportLoading = false
    @State private var viewportFailure: String?
    @State private var viewportCache: [String: (Date, [Place])] = [:]
    var title = "La tua zona"
    var weather = ""
    var heroHeight: CGFloat = 470
    var allowsExpand = true
    var topInset: CGFloat = 0
    var showBrand = false
    var focusedPlace: Place? = nil
    var onAreaResults: (([Place]?) -> Void)? = nil
    var onAreaLoading: ((Bool) -> Void)? = nil
    @State private var expanded = false
    @State private var is3D = true
    @State private var mapDistance: Double = 6500
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var camera: MapCameraPosition = .automatic
    @State private var selection: String?
    @State private var detail: Place?
    private var displayedPlaces: [Place] {
        var merged=Dictionary(places.map { ($0.id,$0) },uniquingKeysWith: { a,_ in a })
        for place in viewportPlaces { merged[place.id]=place }
        let query=searchQuery.trimmingCharacters(in:.whitespacesAndNewlines)
        return merged.values.filter { place in
            if let r = queryRegion {
                let delta = abs(place.longitude-r.center.longitude).truncatingRemainder(dividingBy:360)
                guard abs(place.latitude-r.center.latitude) <= r.span.latitudeDelta/2, min(delta,360-delta) <= r.span.longitudeDelta/2 else { return false }
            }
            return (categoryFilter == "Tutti" || place.category == categoryFilter) && (query.isEmpty || place.name.localizedCaseInsensitiveContains(query) || place.description.localizedCaseInsensitiveContains(query)) }.sorted { $0.id < $1.id }
    }
    private var placeGroups: [MapPlaceGroup] {
        let regular=displayedPlaces
        guard mapDistance > 15000,let region=queryRegion else { return regular.map { MapPlaceGroup(id:$0.id,places:[$0]) } }
        let latStep=max(0.001,region.span.latitudeDelta/9),lonStep=max(0.001,region.span.longitudeDelta/7)
        return Dictionary(grouping:regular) { "\(Int(floor($0.latitude/latStep))):\(Int(floor($0.longitude/lonStep)))" }.map { MapPlaceGroup(id:"cluster-"+$0.key,places:$0.value.sorted{$0.id<$1.id}) }.sorted{$0.id<$1.id}
    }
    private var selectedPlace: Place? { displayedPlaces.first { $0.id == selection } }
    var body: some View {
        VStack(spacing: 0) {
            Map(position: $camera, selection: $selection) {
                Annotation("Tu sei qui", coordinate: coordinate) {
                    ZStack {
                        Circle().fill(RoamStyle.red.opacity(0.12)).frame(width: 44)
                        Circle().fill(RoamStyle.red).frame(width: 14).overlay(Circle().stroke(.white, lineWidth: 3))
                    }.accessibilityLabel("La tua posizione")
                }
                ForEach(placeGroups) { group in
                    if group.places.count == 1, let place=group.places.first {
                        Annotation(place.name,coordinate:place.coordinate,anchor:.bottom) { RoamMapPin(place:place,selected:selection == place.id) }.tag(place.id)
                    } else {
                        Annotation("\(group.places.count) luoghi",coordinate:group.coordinate) {
                            Button { moveCamera(to:group.coordinate,distance:max(700,mapDistance/3)) } label: {
                                Text("\(group.places.count)").font(.headline.monospacedDigit()).foregroundStyle(.white).frame(width:46,height:46).background(RoamStyle.red,in:Circle()).overlay(Circle().stroke(.white,lineWidth:3)).shadow(radius:4)
                            }.accessibilityLabel("Mostra \(group.places.count) luoghi raggruppati")
                        }
                    }
                }
            }
            .onMapCameraChange(frequency:.continuous) { context in
                mapDistance=context.camera.distance
                let r=context.region
                queryRegion=r
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                let r = context.region
                queryRegion = r
                viewportKey = String(format: "%.5f:%.5f:%.5f:%.5f", locale: Locale(identifier: "en_US_POSIX"), r.center.latitude, r.center.longitude, r.span.latitudeDelta, r.span.longitudeDelta)
            }
            .mapStyle(.standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
            .mapControls { MapCompass(); MapScaleView() }
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 7) {
                    if showBrand {
                        HStack(spacing: 5) {
                            RoamMark().stroke(RoamStyle.red, style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round)).frame(width: 25, height: 25)
                            Text("roam").font(.system(.title2, design: .rounded, weight: .heavy)).tracking(-1)
                        }.padding(.bottom, 2).accessibilityLabel("Roam")
                    }
                    Label(title, systemImage: "location.fill").font(.subheadline.bold()).lineLimit(2)
                    if !weather.isEmpty { Label(weather, systemImage: "cloud.sun.fill").font(.caption).foregroundStyle(.secondary) }
                    Text("\(displayedPlaces.count) luoghi nell’area").font(.caption2.weight(.medium)).foregroundStyle(RoamStyle.red).contentTransition(.numericText())
                }.padding(14).frame(maxWidth: 220, alignment: .leading)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 23))
                    .overlay(RoundedRectangle(cornerRadius: 23).stroke(.white.opacity(0.6), lineWidth: 1))
                    .padding(16).padding(.trailing, 60).padding(.top, topInset)
            }
            .overlay(alignment: .topTrailing) {
                VStack(spacing: 12) {
                    Button { recenter() } label: { Image(systemName: "location.north.fill") }.accessibilityLabel("Centra sulla mia posizione")
                    Button { is3D.toggle() } label: { Text(is3D ? "2D" : "3D").font(.caption.bold()) }.accessibilityLabel(is3D ? "Passa alla vista 2D" : "Passa alla vista 3D")
                    if viewportLoading { ProgressView().frame(width:46,height:46).background(.regularMaterial,in:Circle()) }
                    if allowsExpand {
                        Button { expanded = true } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }.accessibilityLabel("Apri la mappa a schermo intero")
                    }
                }.buttonStyle(MapGlassButtonStyle()).padding(16).padding(.top, topInset)
            }
            .overlay(alignment: .bottom) {
                if let place = selectedPlace {
                    Button { detail = place } label: {
                        HStack(spacing: 12) {
                            PlaceGlyph(category: place.category).frame(width: 24, height: 24).foregroundStyle(RoamStyle.red)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(place.name).font(.subheadline.bold()).foregroundStyle(.black).lineLimit(2)
                                Text(String(format: "%.1f km · %@", place.distance, place.category)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right").font(.subheadline.bold()).foregroundStyle(.white).padding(12).background(RoamStyle.red, in: Circle())
                        }.padding(16).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24)).shadow(color: .black.opacity(0.08), radius: 12, y: 4)
                    }.buttonStyle(.plain).padding(12).padding(.bottom, 18).transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .frame(height: compact ? 240 : heroHeight)
            .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8), value: selection)
            .task(id: viewportKey + String(store.viewportSearchEnabled)) {
                guard !viewportKey.isEmpty,let region=queryRegion,store.viewportSearchEnabled else { viewportLoading=false;viewportPlaces=[];onAreaResults?(nil);onAreaLoading?(false);return }
                let key=viewportKey
                onAreaLoading?(true)
                do {
                    try await Task.sleep(for:.milliseconds(550))
                    if let cached=viewportCache[key],Date().timeIntervalSince(cached.0)<600 { viewportPlaces=cached.1;viewportLoading=false;viewportFailure=nil;publishArea(region);onAreaLoading?(false);return }
                    viewportLoading=true;viewportFailure=nil
                    defer { if !Task.isCancelled { viewportLoading=false;onAreaLoading?(false) } }
                    let loaded=try await store.searchViewport(region,origin:coordinate) { partial in
                        viewportPlaces=partial
                        publishArea(region)
                    }
                    try Task.checkCancellation()
                    if viewportCache.count>=20 { viewportCache.removeAll() }
                    viewportCache[key]=(Date(),loaded);viewportPlaces=loaded;publishArea(region)
                } catch { if !Task.isCancelled { viewportLoading=false;viewportFailure="Ricerca nell’area non disponibile";onAreaLoading?(false) } }
            }
            .overlay(alignment:.bottomTrailing) {
                if let viewportFailure { Text(viewportFailure).font(.caption2).padding(8).background(.regularMaterial,in:Capsule()).padding(.bottom,28).padding(.trailing,12) }
            }
            .onChange(of: displayedPlaces.map(\.id)) { _, ids in if let selection, !ids.contains(selection) { self.selection = nil } }
            .task(id: "\(coordinate.latitude),\(coordinate.longitude)") { recenter() }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .sensoryFeedback(.selection, trigger: selection)
        .sheet(item: $detail) { PlaceSheet(place: $0) }
        .onChange(of: focusedPlace?.id) { _, _ in
            guard let place = focusedPlace else { return }
            selection = place.id
            moveCamera(to: place.coordinate, distance: 1800)
        }
        .onChange(of: is3D) { _, _ in moveCamera(to: camera.camera?.centerCoordinate ?? coordinate, distance: mapDistance) }
        .onChange(of: selection) { _, _ in
            guard let place = selectedPlace else { return }
            moveCamera(to: place.coordinate, distance: 2000)
        }
        .fullScreenCover(isPresented: $expanded) {
            NavigationStack {
                GeometryReader { proxy in
                    ExploreMap(places: places, coordinate: coordinate,categoryFilter:categoryFilter,searchQuery:searchQuery,title: title, weather: weather, heroHeight: max(300, proxy.size.height), allowsExpand: false, onAreaResults: onAreaResults, onAreaLoading: onAreaLoading)
                }.navigationTitle("Mappa").roamHeader()
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fine") { expanded = false }.foregroundStyle(RoamStyle.red) } }
            }
        }
    }
    private func publishArea(_ region: MKCoordinateRegion) {
        var merged = Dictionary(places.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for place in viewportPlaces { merged[place.id] = place }
        onAreaResults?(merged.values.filter { place in
            let delta = abs(place.longitude-region.center.longitude).truncatingRemainder(dividingBy: 360)
            return abs(place.latitude-region.center.latitude) <= region.span.latitudeDelta/2 && min(delta,360-delta) <= region.span.longitudeDelta/2
        }.sorted { $0.distance < $1.distance })
    }
    private func legend(_ title: String, _ category: String) -> some View {
        HStack(spacing: 5) { PlaceGlyph(category: category).frame(width: 15, height: 15).foregroundStyle(RoamStyle.red); Text(title).font(.system(size: 10, weight: .medium)) }
    }
    private func recenter() { moveCamera(to: coordinate, distance: compact ? 1800 : 6500) }
    private func moveCamera(to center: CLLocationCoordinate2D, distance: Double) {
        let target = MapCamera(centerCoordinate: center, distance: distance, heading: 0, pitch: is3D ? 45 : 0)
        if reduceMotion { camera = .camera(target) }
        else { withAnimation(.easeInOut(duration: 0.75)) { camera = .camera(target) } }
    }

}
struct TravelDashboard: View {
    let profile: Profile
    let stats: Stats
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Avatar(photo: profile.photo)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bentornato, esploratore").font(.subheadline).foregroundStyle(.secondary)
                    Text(profile.name).font(.title2.bold()).foregroundStyle(.primary)
                }
                Spacer(minLength: 0)
                Image(systemName: "sparkle").font(.title3).foregroundStyle(RoamStyle.red)
            }
            Divider()
            HStack(spacing: 0) {
                metric(stats.posts, "Post", "photo.on.rectangle")
                Spacer(minLength: 6)
                metric(stats.places, "Luoghi", "mappin.and.ellipse")
                Spacer(minLength: 6)
                metric(stats.comments, "Commenti", "bubble.left")
            }
        }.padding(20).background(.white, in: RoundedRectangle(cornerRadius: 26))
            .shadow(color: .black.opacity(0.025), radius: 12, y: 5)
    }
    private func metric(_ value: Int, _ title: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: icon).font(.subheadline).foregroundStyle(RoamStyle.red)
            Text("\(value)").font(.title2.bold()).contentTransition(.numericText())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
struct HomeView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var location: LocationService
    @State private var filter = "Tutti"
    @State private var searchText = ""
    @State private var showPlaceFilters = false
    @State private var areaPlaces: [Place]?
    @State private var areaLoading = false
    private var feedPlaces: [Place] { areaPlaces ?? store.places }
    private var visiblePlaces: [Place] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return feedPlaces.filter { place in
            (filter == "Tutti" || place.category == filter) &&
            (query.isEmpty || place.name.localizedCaseInsensitiveContains(query) || place.category.localizedCaseInsensitiveContains(query) || place.description.localizedCaseInsensitiveContains(query))
        }.sorted { $0.distance < $1.distance }
    }
    @State private var focusedPlace: Place?
    @State private var openedPlace: Place?
    @Namespace private var categorySelection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
            ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    if let coordinate = location.coordinate {
                        ExploreMap(places: store.places, coordinate: coordinate,categoryFilter:filter,searchQuery:searchText,title: location.city, weather: location.weather, heroHeight: 400 + geometry.safeAreaInsets.top, topInset: geometry.safeAreaInsets.top, showBrand: true, focusedPlace: focusedPlace, onAreaResults: { areaPlaces = $0; store.mapAreaPlaces = $0 }, onAreaLoading: { areaLoading = $0 })
                            .id("home-map").padding(.horizontal, -24).padding(.top, -18)
                    } else {
                        VStack(alignment: .leading, spacing: 14) {
                            Label("La tua prossima scoperta", systemImage: "map").font(.title2.bold())
                            Text("Attiva la posizione per esplorare la mappa e i luoghi vicini.").font(.subheadline).foregroundStyle(.secondary)
                            Button("Usa la mia posizione") { location.request() }.buttonStyle(.borderedProminent)
                        }.padding(24).frame(maxWidth: .infinity, alignment: .leading).background(RoamStyle.surface, in: RoundedRectangle(cornerRadius: 28)).padding(.top, geometry.safeAreaInsets.top)
                    }
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(areaPlaces == nil ? "VICINO A TE" : "NELLA ZONA SULLA MAPPA").font(.system(size: 10, weight: .bold)).tracking(2).foregroundStyle(RoamStyle.red)
                            Text("Guardati\nintorno.").font(.system(.largeTitle, design: .rounded, weight: .bold)).tracking(-1.4).lineSpacing(-3)
                        }
                        Spacer()
                        if store.loading || areaLoading { ProgressView() }
                        Button { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { showPlaceFilters.toggle() } } label: {
                            Image(systemName: "line.3.horizontal.decrease").font(.body.weight(.semibold)).foregroundStyle(RoamStyle.red).frame(width: 44, height: 44).background(.white, in: Circle())
                        }.accessibilityLabel(showPlaceFilters ? "Nascondi ricerca e filtri" : "Mostra ricerca e filtri")
                    }
                    if showPlaceFilters {
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass").foregroundStyle(RoamStyle.red)
                        TextField("Cerca luoghi e attrazioni", text: $searchText).font(.subheadline).submitLabel(.search).autocorrectionDisabled()
                        if !searchText.isEmpty {
                            Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.accessibilityLabel("Cancella ricerca")
                        }
                    }.padding(.horizontal, 18).padding(.vertical, 15).background(.white, in: Capsule())
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(["Tutti", "Attrazione", "Parco", "Ristorante", "Caffè", "Negozio"], id: \.self) { category in
                                Button { withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8)) { filter = category } } label: {
                                    HStack(spacing: 7) {
                                        if category != "Tutti" { PlaceGlyph(category: category).frame(width: 18, height: 18) }
                                        Text(category == "Attrazione" ? "Da vedere" : category == "Negozio" ? "Shopping" : category).font(.subheadline.weight(.semibold))
                                    }.padding(.horizontal, 16).padding(.vertical, 12).foregroundStyle(filter == category ? .white : .primary)
                                    .background {
                                        if filter == category { Capsule().fill(RoamStyle.red).matchedGeometryEffect(id: "category", in: categorySelection) }
                                        else { Capsule().fill(.white) }
                                    }
                                }.buttonStyle(.plain).accessibilityAddTraits(filter == category ? .isSelected : [])
                            }
                        }
                    }
                    if !visiblePlaces.isEmpty {
                        HStack {
                            Text("\(visiblePlaces.count) luoghi da scoprire").font(.subheadline.weight(.semibold))
                            Spacer()
                            Label("Più vicini", systemImage: "location.fill").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    LazyVStack(spacing: 24) {
                        ForEach(visiblePlaces) { place in
                            PlaceFeedCard(place: place, onOpen: { openedPlace = place }, onMap: {
                                focusedPlace = nil
                                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.4)) { scrollProxy.scrollTo("home-map", anchor: .top) }
                                Task { @MainActor in await Task.yield(); focusedPlace = place }
                            })
                        }
                    }
                    if let issue = store.placesError {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(issue, systemImage: "wifi.exclamationmark").font(.subheadline)
                            Button("Riprova") { Task { await store.loadPlaces(location.coordinate) } }.disabled(store.loading)
                        }.padding().frame(maxWidth: .infinity, alignment: .leading).background(RoamStyle.surface, in: RoundedRectangle(cornerRadius: 20))
                    }
                    if !store.appleSearchEnabled, location.coordinate != nil {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Cerca anche con Mappe Apple").font(.headline)
                            Text("Attivando questa ricerca, invii la tua posizione ad Apple per trovare luoghi vicini. Puoi disattivarla nel profilo.").font(.caption).foregroundStyle(.secondary)
                            Button("Attiva ricerca con Mappe Apple") {
                                store.appleSearchEnabled = true
                                Task { await store.loadPlaces(location.coordinate) }
                            }.buttonStyle(.borderedProminent)
                        }.padding().background(RoamStyle.surface, in: RoundedRectangle(cornerRadius: 20))
                    }
                    if feedPlaces.isEmpty && !areaLoading {
                        ContentUnavailableView {
                            Label(location.coordinate == nil ? "Esplora la tua zona" : store.loading ? "Cerco luoghi vicini…" : "Nessun luogo caricato", systemImage: "location.magnifyingglass")
                        } description: {
                            Text(location.coordinate == nil ? "Consenti la posizione per trovare attrazioni, caffè e negozi e leggere il meteo locale." : areaPlaces == nil ? "Ricerca entro 5 km. Trascina per riprovare." : "Nessun luogo trovato in quest’area. Sposta o allarga la mappa.")
                        } actions: {
                            if location.permissionDenied { Button("Apri Impostazioni") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } } }
                            else if location.coordinate == nil { Button("Usa la mia posizione") { location.request() } }
                            else { Button("Riprova ricerca") { Task { await store.loadPlaces(location.coordinate) } }.disabled(store.loading) }
                        }
                    }
                    if !feedPlaces.isEmpty && visiblePlaces.isEmpty {
                        ContentUnavailableView.search(text: searchText.isEmpty ? filter : searchText)
                    }
                    HStack(alignment: .top) {
                        Text(areaPlaces == nil ? "Luoghi entro 5 km · " + store.source : "Luoghi nell’area della mappa · Mappe Apple").font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Link(store.source == "Mappe Apple" ? "Mappe Apple" : "© OpenStreetMap", destination: URL(string: store.source == "Mappe Apple" ? "https://maps.apple.com/" : "https://www.openstreetmap.org/copyright")!).font(.caption2)
                        Link("Open-Meteo", destination: URL(string: "https://open-meteo.com/")!).font(.caption2)
                    }.padding(.top, 2)
                }.padding(.horizontal, 24).padding(.vertical, 18)
            }.scrollDismissesKeyboard(.interactively).background(RoamStyle.canvas)
                .toolbar(.hidden, for: .navigationBar)
                .ignoresSafeArea(edges: .top)
                .sensoryFeedback(.selection, trigger: filter)
                .sheet(item: $openedPlace) { PlaceSheet(place: $0) }
                .refreshable { await store.load(location.coordinate); await location.refreshWeather() }
            }
            }
        }
    }
}
@MainActor final class PlaceImageCache {
    static let shared = PlaceImageCache()
    let images = NSCache<NSString, UIImage>()
    init() { images.countLimit = 60 }
}
struct PlaceVisual: View {
    let place:Place
    var height:CGFloat=188
    var prominent=false
    @EnvironmentObject var store:Store
    @State private var failed=false
    private var uploaded:UIImage? {
        guard let photo=store.activity[place.id]?.photo,let data=Data(base64Encoded:photo) else { return nil }
        return UIImage(data:data)
    }
    var body:some View {
        ZStack(alignment:.bottomLeading) {
            if let image=uploaded {
                GeometryReader { p in Image(uiImage:image).resizable().scaledToFill().frame(width:p.size.width,height:p.size.height).clipped() }
            } else if let photo=store.webPhotos[place.id],let url=URL(string:photo.url),!failed {
                AsyncImage(url:url) { phase in
                    if let image=phase.image { GeometryReader { p in image.resizable().scaledToFill().frame(width:p.size.width,height:p.size.height).clipped() } }
                    else if phase.error != nil { placeholder.onAppear { if !store.nextWebPhoto(place) { failed=true } } }
                    else { placeholder.overlay { ProgressView() } }
                }.id(photo.url)
            } else { placeholder }
            LinearGradient(colors:[.clear,.black.opacity(0.4)],startPoint:.center,endPoint:.bottom).allowsHitTesting(false)
            Text(uploaded != nil ? "Foto della community" : store.webPhotos[place.id] != nil && !failed ? (store.webPhotos[place.id]?.provider == "google_images" ? "Google Immagini · fonte verificata" : "Wikimedia Commons") : "Foto non disponibile")
                .font(.caption2.weight(.medium)).foregroundStyle(.white).padding(.horizontal,9).padding(.vertical,6).background(.black.opacity(0.35),in:Capsule()).padding(12)
                .frame(maxWidth:.infinity,maxHeight:.infinity,alignment:prominent ? .topTrailing : .bottomLeading).padding(.top,prominent ? 44 : 0)
        }.frame(height:height).clipped().task(id:place.id) { await store.loadWebPhoto(place) }
    }
    private var placeholder:some View { ZStack { RoamStyle.surface;PlaceGlyph(category:place.category).frame(width:48,height:48).foregroundStyle(RoamStyle.red.opacity(0.5)) } }
}
struct DiscoveryPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
// Decoding multi-megabyte base64 photos on every render makes scrolling stutter.
// Feed and profile use only white, red and black.
struct RoamTabs: View {
    let options: [String]
    @Binding var selection: String
    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                Button { withAnimation(.easeOut(duration: 0.2)) { selection = option } } label: {
                    VStack(spacing: 6) {
                        Text(option).font(.subheadline.weight(selection == option ? .bold : .regular))
                            .foregroundStyle(selection == option ? RoamStyle.red : .black)
                        Capsule().fill(selection == option ? RoamStyle.red : .clear).frame(width: 28, height: 2)
                    }.frame(maxWidth: .infinity).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityAddTraits(selection == option ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}
struct RoamEmptyState: View {
    let icon, title, message: String
    var action: String? = nil
    var perform: () -> Void = {}
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 40)).foregroundStyle(RoamStyle.red)
            Text(title).font(.title3.bold()).foregroundStyle(.black).multilineTextAlignment(.center)
            Text(message).font(.subheadline).foregroundStyle(.black).multilineTextAlignment(.center)
            if let action {
                Button(action: perform) {
                    Text(action).font(.subheadline.bold()).foregroundStyle(.white).padding(.horizontal, 20).frame(height: 40).background(RoamStyle.red, in: Capsule())
                }.buttonStyle(DiscoveryPressStyle()).padding(.top, 4)
            }
        }.frame(maxWidth: .infinity).padding(.horizontal, 32)
    }
}
@MainActor enum PostImageCache {
    private static let cache = NSCache<NSString, UIImage>()
    static func image(_ post: SocialPost) -> UIImage? {
        guard let photo = post.photo else { return nil }
        if let hit = cache.object(forKey: post.id as NSString) { return hit }
        guard let data = Data(base64Encoded: photo), let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: post.id as NSString)
        return image
    }
}
struct SocialFeedView: View {
    @EnvironmentObject private var store: Store
    @State private var scope = "Vicino a te"
    @State private var composing = false
    @State private var commenting: SocialPost?
    @State private var openedPlace: Place?
    private var areaPlaces: [Place] { scope == "Sulla mappa" ? store.mapAreaPlaces ?? store.places : store.places }
    private var queryKey: String { scope + "|" + (scope == "Salvati" ? "saved" : areaPlaces.map(\.id).sorted().joined(separator: "|")) }
    private var posts: [SocialPost] { store.socialPosts.filter { scope != "Salvati" || $0.saved } }
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    RoamTabs(options: ["Vicino a te", "Sulla mappa", "Salvati"], selection: $scope).padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 12)
                    if scope == "Sulla mappa" {
                        Label("I post dei luoghi nell’ultima zona esplorata sulla Mappa.", systemImage: "map").font(.caption).foregroundStyle(.black).padding(.horizontal, 16).padding(.bottom, 12)
                    }
                    if scope != "Salvati" {
                        Button { composing = true } label: {
                            HStack(spacing: 12) {
                                Avatar(photo: store.profile.photo, size: 38)
                                Text("Che posto hai scoperto?").font(.subheadline).foregroundStyle(.black)
                                Spacer(minLength: 0)
                                Image(systemName: "photo.badge.plus").font(.title3).foregroundStyle(RoamStyle.red)
                            }.padding(.horizontal, 16).padding(.vertical, 10).contentShape(Rectangle())
                        }.buttonStyle(.plain).padding(.bottom, 6)
                    }
                    if let issue = store.socialError {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(issue).font(.subheadline)
                            Button("Riprova") { Task { await reload() } }
                        }.padding(16)
                    }
                    if posts.isEmpty && !store.socialLoading && store.socialError == nil {
                        RoamEmptyState(icon: scope == "Salvati" ? "bookmark" : "photo.on.rectangle.angled", title: scope == "Salvati" ? "Le storie da conservare" : "La prima storia può essere la tua", message: scope == "Salvati" ? "Salva un post con il segnalibro e lo ritroverai qui." : areaPlaces.isEmpty ? "Esplora la mappa per caricare i luoghi, poi condividi la tua esperienza." : "Qui troverai foto e racconti dei luoghi di questa zona. Condividi la tua prima scoperta.", action: scope == "Salvati" ? nil : "Pubblica un’esperienza") { composing = true }.padding(.top, 40)
                    }
                    ForEach(posts) { post in
                        SocialPostCard(post: post, place: areaPlaces.first { $0.id == post.place_id } ?? post.place, onPlace: {
                            openedPlace = areaPlaces.first { $0.id == post.place_id } ?? post.place
                        }, onComment: { commenting = post })
                    }
                    if store.socialLoading { ProgressView("Carico le esperienze…").frame(maxWidth: .infinity).padding() }
                    if store.socialHasMore && !store.socialLoading {
                        Color.clear.frame(height: 1).onAppear { Task { await store.loadSocialFeed(ids: areaPlaces.map(\.id), savedOnly: scope == "Salvati", append: true) } }
                    }
                }
            }.background(Color.white).navigationTitle("Feed").roamHeader()
                .toolbar {
                    ToolbarItem(placement: .primaryAction) { Button { composing = true } label: { Image(systemName: "plus.app") }.accessibilityLabel("Pubblica un’esperienza") }
                }
                .task(id: queryKey) {
                    do { try await Task.sleep(for: .milliseconds(350)); try Task.checkCancellation() } catch { return }
                    await reload()
                }
                .refreshable { await reload() }
                .sheet(isPresented: $composing) { SocialComposer(places: store.knownPlaces) { _ in Task { await reload() } } }
                .sheet(item: $commenting) { SocialCommentsView(post: $0) }
                .sheet(item: $openedPlace) { PlaceSheet(place: $0) }
        }
    }
    private func reload() async { await store.loadSocialFeed(ids: areaPlaces.map(\.id), savedOnly: scope == "Salvati") }
}

struct SocialPostCard: View {
    let post: SocialPost
    let place: Place
    let onPlace: () -> Void
    let onComment: () -> Void
    var onDeleted: (() -> Void)? = nil
    @EnvironmentObject private var store: Store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var saving = false
    @State private var confirmDelete = false
    @State private var deleting = false
    @State private var expanded = false
    @State private var burst = false
    private var image: UIImage? { PostImageCache.image(post) }
    private var dateLabel: String {
        let parser = ISO8601DateFormatter(); parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = parser.date(from: post.created_at) ?? ISO8601DateFormatter().date(from: post.created_at) else { return "" }
        if Date().timeIntervalSince(date) > 7 * 86400 { return date.formatted(.dateTime.day().month(.wide).year()) }
        let relative = RelativeDateTimeFormatter(); relative.locale = Locale(identifier: "it_IT")
        return relative.localizedString(for: date, relativeTo: Date())
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                if post.mine { Avatar(photo: store.profile.photo, size: 34) }
                else {
                    Text(String(post.author.prefix(1)).uppercased()).font(.subheadline.bold()).foregroundStyle(RoamStyle.red)
                        .frame(width: 34, height: 34).background(RoamStyle.red.opacity(0.08), in: Circle())
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(post.mine ? store.profile.name : post.author).font(.subheadline.bold()).lineLimit(1)
                    Button(action: onPlace) {
                        HStack(spacing: 3) { Image(systemName: "mappin"); Text(place.name).lineLimit(1) }.font(.caption)
                    }.buttonStyle(.plain).accessibilityLabel("Luogo: \(place.name). Apri")
                }
                Spacer(minLength: 4)
                Menu {
                    Button { onPlace() } label: { Label("Vedi il luogo", systemImage: "mappin.circle") }
                    Button { directions() } label: { Label("Portami qui", systemImage: "arrow.triangle.turn.up.right.diamond") }
                    if post.mine {
                        Divider()
                        Button(role: .destructive) { confirmDelete = true } label: { Label("Elimina post", systemImage: "trash") }
                    }
                } label: { Image(systemName: "ellipsis").font(.body.weight(.semibold)).foregroundStyle(.primary).frame(width: 36, height: 36).contentShape(Rectangle()) }
                    .accessibilityLabel("Altre azioni")
            }.padding(.horizontal, 12).padding(.vertical, 8)
            ZStack {
                if let image {
                    Color.clear.aspectRatio(4 / 5, contentMode: .fit)
                        .overlay { Image(uiImage: image).resizable().scaledToFill() }.clipped()
                } else { PlaceVisual(place: place, height: 320) }
                Image(systemName: "bookmark.fill").font(.system(size: 72)).foregroundStyle(.white).shadow(radius: 10)
                    .scaleEffect(burst ? 1 : 0.4).opacity(burst ? 1 : 0).allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { saveFromDoubleTap() }
            .accessibilityAction(named: "Salva") { saveFromDoubleTap() }
            .accessibilityLabel("Foto di \(place.name)")
            HStack(spacing: 16) {
                Button(action: onComment) { Image(systemName: "bubble.right") }.accessibilityLabel("Commenta")
                share
                Button { directions() } label: { Image(systemName: "paperplane") }.accessibilityLabel("Portami qui")
                Spacer()
                Button {
                    saving = true
                    Task { await store.toggleSaved(post); saving = false }
                } label: { Image(systemName: post.saved ? "bookmark.fill" : "bookmark") }.disabled(saving).accessibilityLabel(post.saved ? "Rimuovi dai salvati" : "Salva esperienza")
            }.font(.title3).foregroundStyle(.primary).buttonStyle(.plain).padding(.horizontal, 14).padding(.top, 10)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 2) { ForEach(0..<5) { i in Image(systemName: i < post.rating ? "star.fill" : "star").font(.caption2) } }
                    .foregroundStyle(RoamStyle.red).accessibilityElement(children: .ignore).accessibilityLabel("Valutazione \(post.rating) su 5")
                Text("\(Text(post.mine ? store.profile.name : post.author).bold()) \(post.body)").font(.subheadline)
                    .lineLimit(expanded ? nil : 2).fixedSize(horizontal: false, vertical: true)
                    .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { expanded.toggle() } }
                Button(action: onComment) {
                    Text(post.comments == 0 ? "Aggiungi un commento…" : post.comments == 1 ? "Visualizza 1 commento" : "Visualizza tutti i \(post.comments) commenti")
                        .font(.subheadline).foregroundStyle(.black)
                }.buttonStyle(.plain)
                Text(dateLabel).font(.caption2).foregroundStyle(.black)
            }.padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 18)
        }
        .opacity(deleting ? 0.4 : 1).disabled(deleting)
        .confirmationDialog("Eliminare il post?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Elimina", role: .destructive) {
                deleting = true
                Task { if await store.deletePost(post) { onDeleted?() }; deleting = false }
            }
            Button("Annulla", role: .cancel) {}
        } message: { Text("Il post e i suoi commenti verranno rimossi da Feed e Profilo.") }
    }
    @ViewBuilder private var share: some View {
        if let image {
            let preview = Image(uiImage: image)
            ShareLink(item: preview, subject: Text(place.name), message: Text("\(place.name) — \(post.body)"), preview: SharePreview(place.name, image: preview)) { Image(systemName: "square.and.arrow.up") }
        } else {
            ShareLink(item: "\(place.name) — \(post.body)") { Image(systemName: "square.and.arrow.up") }
        }
    }
    private func directions() {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: place.coordinate)); item.name = place.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }
    // Like Instagram's double-tap: only ever adds, never removes.
    private func saveFromDoubleTap() {
        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.55)) { burst = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { withAnimation(.easeOut(duration: 0.25)) { burst = false } }
        guard !post.saved, !saving else { return }
        saving = true
        Task { await store.toggleSaved(post); saving = false }
    }
}

struct PlaceChooser: View {
    let places: [Place]
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    private var filtered: [Place] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? places : places.filter { $0.name.localizedCaseInsensitiveContains(q) || $0.category.localizedCaseInsensitiveContains(q) }
    }
    var body: some View {
        List(filtered) { place in
            Button { selection = place.id; dismiss() } label: {
                HStack(spacing: 12) {
                    PlaceGlyph(category: place.category).frame(width: 22, height: 22).foregroundStyle(RoamStyle.red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(place.name).foregroundStyle(.primary)
                        Text("\(place.category) · \(place.distance < 1 ? "\(Int(place.distance * 1000)) m" : String(format: "%.1f km", place.distance))").font(.caption).foregroundStyle(.black)
                    }
                    Spacer()
                    if place.id == selection { Image(systemName: "checkmark").foregroundStyle(RoamStyle.red) }
                }
            }
        }
        .listStyle(.plain).scrollContentBackground(.hidden).background(Color.white)
        .overlay { if filtered.isEmpty { RoamEmptyState(icon: "magnifyingglass", title: "Nessun luogo", message: "Nessun risultato per “\(query)”.") } }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Cerca un luogo")
        .navigationTitle("Aggiungi luogo").roamHeader()
    }
}

struct SocialComposer: View {
    let places: [Place]
    let onPublished: (SocialPost) -> Void
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var placeID = ""
    @State private var caption = ""
    @State private var rating = 5
    @State private var selection: PhotosPickerItem?
    @State private var photo: String?
    @State private var loadingPhoto = false
    @State private var publishing = false
    @State private var failure: String?
    private var place: Place? { places.first { $0.id == placeID } }
    private var valid: Bool { !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && caption.count <= 2000 && photo != nil && place != nil }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PhotosPicker(selection: $selection, matching: .images) {
                        ZStack {
                            if let photo, let data = Data(base64Encoded: photo), let image = UIImage(data: data) {
                                Color.clear.aspectRatio(4 / 5, contentMode: .fit).overlay { Image(uiImage: image).resizable().scaledToFill() }.clipped()
                            } else {
                                VStack(spacing: 10) {
                                    Image(systemName: "photo.on.rectangle.angled").font(.system(size: 40)).foregroundStyle(RoamStyle.red)
                                    Text("Scegli una foto").font(.headline).foregroundStyle(.primary)
                                }.frame(maxWidth: .infinity).frame(height: 240).background(.white)
                            }
                            if loadingPhoto { ProgressView().controlSize(.large) }
                        }
                    }.disabled(publishing || loadingPhoto).listRowInsets(EdgeInsets())
                } footer: { if photo != nil { Text("Tocca la foto per cambiarla.") } }
                Section {
                    TextField("Scrivi una didascalia…", text: $caption, axis: .vertical).lineLimit(3...8)
                    Text("\(caption.count)/2000").font(.caption).foregroundStyle(caption.count > 2000 ? RoamStyle.red : .black)
                }
                Section {
                    if places.isEmpty { Text("Esplora la mappa per caricare i luoghi vicini: ogni post è collegato a un luogo.").foregroundStyle(.black) }
                    else {
                        NavigationLink { PlaceChooser(places: places, selection: $placeID) } label: {
                            HStack {
                                Label(place?.name ?? "Aggiungi luogo", systemImage: place == nil ? "mappin.and.ellipse" : "mappin.circle.fill")
                                    .foregroundStyle(place == nil ? RoamStyle.red : .primary)
                                Spacer()
                                if place == nil { Text("Obbligatorio").font(.caption).foregroundStyle(.black) }
                            }
                        }
                    }
                    Picker("Valutazione", selection: $rating) { ForEach(1...5, id: \.self) { Text(String(repeating: "★", count: $0)).tag($0) } }
                } header: { Text("Luogo") } footer: {
                    Text("Ogni post è legato a un luogo. Pubblicato come \(store.profile.name); foto e testo vengono salvati sul backend di Roam.")
                }
                if let failure { Section { Text(failure).foregroundStyle(.red) } }
            }.disabled(publishing).scrollContentBackground(.hidden).background(Color.white).listSectionSeparator(.hidden).tint(RoamStyle.red)
                .navigationTitle("Nuovo post").roamHeader()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() }.disabled(publishing) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button { publish() } label: { if publishing { ProgressView() } else { Text("Condividi").bold() } }.disabled(!valid || publishing || loadingPhoto)
                    }
                }.interactiveDismissDisabled(publishing || loadingPhoto)
                .onChange(of: selection) { _, item in
                    Task {
                        loadingPhoto = true; defer { loadingPhoto = false }
                        do {
                            guard let data = try await item?.loadTransferable(type: Data.self), let image = UIImage(data: data) else { throw URLError(.cannotDecodeContentData) }
                            let ratio = min(1, 1200 / max(image.size.width, image.size.height))
                            let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
                            let resized = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
                            guard let jpeg = resized.jpegData(compressionQuality: 0.75) else { throw URLError(.cannotDecodeContentData) }
                            photo = jpeg.base64EncodedString(); failure = nil
                        } catch { failure = "Foto non leggibile. Scegli un’altra immagine." }
                    }
                }
        }
    }
    private func publish() {
        guard let place, let photo else { return }
        publishing = true; failure = nil
        Task {
            defer { publishing = false }
            do {
                try await store.register(place)
                let payload = try JSONSerialization.data(withJSONObject: ["place_id": place.id, "body": caption, "rating": rating, "photo": photo])
                let post: SocialPost = try await store.request("/feed/posts", method: "POST", body: payload)
                store.published(post)
                onPublished(post); dismiss()
            } catch { failure = error.localizedDescription }
        }
    }
}

struct SocialCommentsView: View {
    let post: SocialPost
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var comments: [SocialComment] = []
    @State private var text = ""
    @State private var loading = true
    @State private var sending = false
    @State private var failure: String?
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    Section {
                        Text(post.place.name).font(.headline)
                        Text(post.body).font(.subheadline).foregroundStyle(.black).lineLimit(4)
                    }
                    Section("Conversazione") {
                        if loading { ProgressView("Carico i commenti…") }
                        else if comments.isEmpty && failure == nil { Text("Inizia la conversazione.").foregroundStyle(.black) }
                        ForEach(comments) { comment in
                            VStack(alignment: .leading, spacing: 6) { Text(comment.author).font(.subheadline.bold()); Text(comment.body).font(.subheadline) }.padding(.vertical, 5)
                        }
                    }
                    if let failure { Section { Text(failure).foregroundStyle(RoamStyle.red); Button("Riprova") { Task { await load() } } } }
                }.listStyle(.plain).scrollContentBackground(.hidden).background(Color.white)
                HStack(alignment: .bottom, spacing: 12) {
                    TextField("Scrivi un commento…", text: $text, axis: .vertical).lineLimit(1...5).padding(12).background(.white, in: RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.black, lineWidth: 1))
                    Button { send() } label: { Image(systemName: "arrow.up").font(.headline).foregroundStyle(.white).frame(width: 42, height: 42).background(RoamStyle.red, in: Circle()) }
                        .disabled(sending || loading || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.count > 1000).accessibilityLabel("Pubblica commento")
                }.padding().background(.white)
            }.navigationTitle("Commenti").roamHeader()
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fine") { dismiss() } } }.task { await load() }
        }
    }
    private func load() async {
        loading = true; defer { loading = false }
        do { comments = try await store.request("/feed/posts/\(post.id)/comments"); failure = nil }
        catch { failure = "Commenti non disponibili. Riprova." }
    }
    private func send() {
        sending = true
        Task {
            defer { sending = false }
            do {
                let payload = try JSONSerialization.data(withJSONObject: ["body": text])
                let comment: SocialComment = try await store.request("/feed/posts/\(post.id)/comments", method: "POST", body: payload)
                comments.append(comment); text = ""; failure = nil
                // Reload the count without discarding the current feed or its pagination.
                store.updatePost(post.id) { $0.comments = comments.count }
            } catch { failure = "Invio non riuscito. Il testo è conservato: riprova." }
        }
    }
}

struct PlaceFeedCard: View {
    let place: Place
    let onOpen: () -> Void
    let onMap: () -> Void
    @EnvironmentObject private var store: Store
    private var distance: String {
        place.distance < 1 ? "\(Int(place.distance * 1000)) m" : String(format: "%.1f km", place.distance)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onOpen) {
                PlaceVisual(place: place, height: 230)
                    .overlay(alignment: .topLeading) {
                        Label(place.category, systemImage: "sparkle").font(.caption.bold())
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .foregroundStyle(.white).background(RoamStyle.red, in: Capsule()).padding(16)
                    }
            }.buttonStyle(DiscoveryPressStyle()).accessibilityLabel("Scopri \(place.name)")
            VStack(alignment: .leading, spacing: 14) {
                Button(action: onOpen) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(place.name).font(.system(.title2, design: .rounded, weight: .bold)).foregroundStyle(.primary).multilineTextAlignment(.leading)
                            Label("\(distance) da te", systemImage: "location").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        if let rating = store.activity[place.id]?.rating {
                            Label(String(format: "%.1f", rating), systemImage: "star.fill").font(.caption.bold()).foregroundStyle(RoamStyle.red)
                        }
                    }
                }.buttonStyle(.plain)
                Text(place.description).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                HStack(spacing: 10) {
                    Button(action: onMap) { Label("Mappa", systemImage: "map") }
                        .buttonStyle(.bordered).tint(RoamStyle.red)
                    Button {
                        let item = MKMapItem(placemark: MKPlacemark(coordinate: place.coordinate))
                        item.name = place.name
                        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
                    } label: { Label("Indicazioni", systemImage: "arrow.turn.up.right") }
                        .buttonStyle(.borderedProminent).tint(RoamStyle.red)
                }.font(.subheadline.weight(.semibold))
                Divider()
                Button(action: onOpen) {
                    HStack {
                        Label(store.activity[place.id].map { "\($0.comments) commenti · Di’ la tua" } ?? "Commenta questo luogo", systemImage: "bubble.left.and.bubble.right")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }.font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }.buttonStyle(.plain)
            }.padding(18)
        }.background(.white, in: RoundedRectangle(cornerRadius: 28))
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(.black.opacity(0.04)))
            .shadow(color: .black.opacity(0.04), radius: 16, y: 6)
            .task(id: place.id) { await store.refreshActivity(place) }
    }
}
struct PlaceCard: View {
    let place: Place
    @EnvironmentObject var store: Store
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            PlaceVisual(place: place, height: 360, prominent: true)
            LinearGradient(stops: [.init(color: .clear, location: 0.3), .init(color: .black.opacity(0.85), location: 1)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 12) {
                Text(place.name).font(.system(.title, design: .rounded, weight: .bold)).tracking(-0.8).foregroundStyle(.white).lineLimit(2)
                HStack(spacing: 7) {
                    Image(systemName: "location").font(.caption)
                    Text(String(format: "%.1f km da te", place.distance)).font(.subheadline)
                    if let rating = store.activity[place.id]?.rating {
                        Text("·"); Image(systemName: "star.fill").font(.caption); Text(String(format: "%.1f", rating)).font(.subheadline.bold())
                    }
                }.foregroundStyle(.white.opacity(0.85))
                HStack {
                    Label(store.activity[place.id].map { "\($0.comments) commenti" } ?? "Scopri il luogo", systemImage: "bubble.left").font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.85))
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.headline).foregroundStyle(.black).frame(width: 44, height: 44).background(.white, in: Circle())
                }
            }.padding(22)
        }.overlay(alignment: .topLeading) {
            HStack(spacing: 6) { PlaceGlyph(category: place.category).frame(width: 16, height: 16); Text(place.category).font(.caption.bold()) }
                .foregroundStyle(.white).padding(.horizontal, 13).padding(.vertical, 9).background(RoamStyle.red, in: Capsule()).padding(16)
        }.clipShape(RoundedRectangle(cornerRadius: 30))
            .contentShape(RoundedRectangle(cornerRadius: 30))
            .task(id: place.id) { await store.refreshActivity(place) }
    }
}
struct PlaceView: View {
    let place: Place
    @EnvironmentObject var store: Store
    @State private var reviews: [Review] = []
    @State private var bodyText = ""
    @State private var rating = 5
    @State private var sending = false
    @State private var placePhoto: PhotosPickerItem?
    @State private var savingPhoto = false
    private var googleImagesURL: URL? {
        var components = URLComponents(string: "https://www.google.com/search")!
        components.queryItems = [URLQueryItem(name: "tbm", value: "isch"), URLQueryItem(name: "q", value: "\(place.name) \(place.description) \(place.latitude) \(place.longitude)")]
        return components.url
    }
    @State private var reviewError: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PlaceVisual(place: place).clipShape(RoundedRectangle(cornerRadius: 26))
                if let photo=store.webPhotos[place.id],let url=URL(string:photo.source_url) {
                    Link(destination:url) { Text("Foto: \(photo.author) · \(photo.license) · \(photo.provider == "google_images" ? "Google Immagini" : "Wikimedia Commons")").font(.caption) }
                }
                if let searchURL = googleImagesURL {
                    Link(destination: searchURL) { Label("Cerca foto su Google Immagini", systemImage: "magnifyingglass") }
                    Text("Verifica nome e indirizzo del locale, poi salva e aggiungi la foto corretta.").font(.caption).foregroundStyle(.secondary)
                }
                PhotosPicker(selection: $placePhoto, matching: .images) { Label(savingPhoto ? "Salvataggio foto…" : "Aggiungi una foto del luogo", systemImage: "camera") }.disabled(savingPhoto)
                Text("La foto scelta viene salvata sul backend e diventa la copertina del luogo.").font(.caption).foregroundStyle(.secondary)
                Map(initialPosition: .region(.init(center: place.coordinate, span: .init(latitudeDelta: 0.012, longitudeDelta: 0.012)))) {
                    Annotation(place.name, coordinate: place.coordinate, anchor: .bottom) {
                        RoamMapPin(place: place, selected: true)
                    }
                }.mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false)).frame(height: 260).clipShape(RoundedRectangle(cornerRadius: 28))
                Text(place.category).font(.caption.bold()).foregroundStyle(RoamStyle.red)
                Text(place.description).font(.title3)
                Text("Commenti della community").font(.title2.bold())
                if let reviewError { Text(reviewError).font(.caption).foregroundStyle(.secondary) }
                if reviews.isEmpty && reviewError == nil { Text("Condividi per primo la tua esperienza.").foregroundStyle(.secondary) }
                ForEach(reviews) { review in VStack(alignment: .leading, spacing: 6) { HStack { Text(review.author).bold(); Spacer(); Text(String(repeating: "★", count: review.rating)).foregroundStyle(RoamStyle.red) }; Text(review.body) }.padding().background(RoamStyle.surface, in: RoundedRectangle(cornerRadius: 16)) }
                TextField("Com’è stata la tua visita?", text: $bodyText, axis: .vertical).textFieldStyle(.roundedBorder)
                Picker("Valutazione", selection: $rating) { ForEach(1...5, id: \.self) { Text("\($0) ★").tag($0) } }
                Button(sending ? "Invio…" : "Pubblica commento") {
                    sending = true
                    Task {
                        defer { sending = false }
                        do {
                            try await store.register(place)
                            let data = try JSONSerialization.data(withJSONObject: ["author": store.profile.name, "body": bodyText, "rating": rating])
                            let review: Review = try await store.request("/places/\(place.id)/comments", method: "POST", body: data)
                            reviews.insert(review, at: 0); bodyText = ""; reviewError = nil
                            await store.refreshActivity(place)
                            store.stats = try await store.request("/stats")
                        } catch { store.error = error.localizedDescription }
                    }
                }.buttonStyle(.borderedProminent).disabled(bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
            }.padding(20)
        }.navigationTitle(place.name).navigationBarTitleDisplayMode(.inline).roamHeader()
            .task {
                await store.refreshActivity(place)
                do { try await store.register(place); reviews = try await store.request("/places/\(place.id)/comments") }
                catch { reviewError = "Commenti non disponibili. Controlla la connessione al backend." }
            }
            .onChange(of: placePhoto) { _, item in
                Task {
                    savingPhoto = true; defer { savingPhoto = false }
                    do {
                        guard let data = try await item?.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
                        let ratio = min(1, 1200 / max(image.size.width, image.size.height))
                        let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
                        let resized = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
                        guard let jpeg = resized.jpegData(compressionQuality: 0.75) else { return }
                        try await store.register(place)
                        let payload = try JSONSerialization.data(withJSONObject: ["photo": jpeg.base64EncodedString()])
                        let activity: PlaceActivity = try await store.request("/places/\(place.id)/photo", method: "PUT", body: payload)
                        store.activity[place.id] = activity
                    } catch { store.error = error.localizedDescription }
                }
            }
    }
}
struct SearchActivity: Identifiable, Hashable {
    let title, query, category, icon: String
    var id: String { title }
    static let all = [
        SearchActivity(title: "Musei e cultura", query: "musei", category: "Attrazione", icon: "building.columns.fill"),
        SearchActivity(title: "Monumenti", query: "monumenti e siti storici", category: "Attrazione", icon: "building.columns"),
        SearchActivity(title: "Panorami", query: "punti panoramici", category: "Attrazione", icon: "binoculars.fill"),
        SearchActivity(title: "Parchi e natura", query: "parchi e giardini", category: "Parco", icon: "leaf.fill"),
        SearchActivity(title: "Mangiare fuori", query: "ristoranti", category: "Ristorante", icon: "fork.knife"),
        SearchActivity(title: "Pizza", query: "pizzerie", category: "Ristorante", icon: "flame.fill"),
        SearchActivity(title: "Caffè e colazioni", query: "caffè", category: "Caffè", icon: "cup.and.saucer.fill"),
        SearchActivity(title: "Gelato e dolci", query: "gelaterie e pasticcerie", category: "Caffè", icon: "birthday.cake.fill"),
        SearchActivity(title: "Shopping", query: "negozi", category: "Negozio", icon: "bag.fill"),
        SearchActivity(title: "Librerie e mercati", query: "librerie e mercati", category: "Negozio", icon: "books.vertical.fill")
    ]
}
struct SearchPlaceRow: View {
    let place: Place
    private var distance: String { place.distance < 1 ? "\(Int(place.distance * 1000)) m" : String(format: "%.1f km", place.distance) }
    var body: some View {
        HStack(spacing: 14) {
            PlaceGlyph(category: place.category).frame(width: 22, height: 22).foregroundStyle(RoamStyle.red)
                .frame(width: 48, height: 48).background(RoamStyle.red.opacity(0.08), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(place.name).font(.subheadline.bold()).foregroundStyle(.primary).lineLimit(1)
                Text("\(place.category == "Attrazione" ? "Da vedere" : place.category == "Negozio" ? "Shopping" : place.category) · \(distance)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }.padding(.horizontal, 16).padding(.vertical, 12).contentShape(Rectangle())
    }
}
struct PersonRow: View {
    let person: Person
    @EnvironmentObject private var store: Store
    var body: some View {
        HStack(spacing: 14) {
            if person.mine { Avatar(photo: store.profile.photo, size: 48) }
            else {
                Text(String(person.name.prefix(1)).uppercased()).font(.headline).foregroundStyle(RoamStyle.red)
                    .frame(width: 48, height: 48).background(RoamStyle.red.opacity(0.08), in: Circle())
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(person.mine ? store.profile.name : person.name).font(.subheadline.bold()).foregroundStyle(.primary).lineLimit(1)
                    if person.mine { Text("Tu").font(.caption2.bold()).foregroundStyle(.white).padding(.horizontal, 7).padding(.vertical, 2).background(RoamStyle.red, in: Capsule()) }
                }
                Text("\(person.posts) \(person.posts == 1 ? "esperienza" : "esperienze") · \(person.places) \(person.places == 1 ? "luogo" : "luoghi")").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }.padding(.horizontal, 16).padding(.vertical, 12).contentShape(Rectangle())
    }
}
struct SearchView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var location: LocationService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scope = "Luoghi"
    @State private var query = ""
    @State private var activity: SearchActivity?
    @State private var appleResults: [Place] = []
    @State private var searching = false
    @State private var searchFailure: String?
    @State private var people: [Person] = []
    @State private var peopleLoaded = false
    @State private var peopleError: String?
    @State private var openedPlace: Place?
    @FocusState private var fieldFocused: Bool
    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var placeResults: [Place] {
        var seen = Set<String>()
        let local = store.knownPlaces.filter { place in
            if scope == "Attività" { return activity.map { place.category == $0.category } ?? false }
            return trimmed.isEmpty || place.name.localizedCaseInsensitiveContains(trimmed) || place.category.localizedCaseInsensitiveContains(trimmed) || place.description.localizedCaseInsensitiveContains(trimmed)
        }
        return (appleResults + local).filter { seen.insert($0.id).inserted }.sorted { $0.distance < $1.distance }
    }
    private var activities: [SearchActivity] {
        trimmed.isEmpty ? SearchActivity.all : SearchActivity.all.filter { $0.title.localizedCaseInsensitiveContains(trimmed) || $0.query.localizedCaseInsensitiveContains(trimmed) }
    }
    private var searchKey: String { scope + "|" + trimmed + "|" + (activity?.id ?? "") + "|" + String(store.appleSearchEnabled) + "|" + (location.coordinate.map { "\(Int($0.latitude * 100)),\(Int($0.longitude * 100))" } ?? "") }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("CERCA").font(.system(size: 10, weight: .bold)).tracking(2).foregroundStyle(RoamStyle.red)
                        Text("Trova il tuo\nprossimo posto.").font(.system(.largeTitle, design: .rounded, weight: .bold)).tracking(-1.4).lineSpacing(-3)
                    }.padding(.horizontal, 24)
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass").foregroundStyle(RoamStyle.red)
                        TextField(scope == "Persone" ? "Cerca viaggiatori" : scope == "Attività" ? "Cosa ti va di fare?" : "Cerca luoghi e attrazioni", text: $query)
                            .font(.subheadline).submitLabel(.search).autocorrectionDisabled().focused($fieldFocused)
                        if !query.isEmpty {
                            Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.accessibilityLabel("Cancella ricerca")
                        }
                    }.padding(.horizontal, 18).padding(.vertical, 15).background(.white, in: Capsule()).padding(.horizontal, 24)
                    RoamTabs(options: ["Luoghi", "Attività", "Persone"], selection: $scope).padding(.horizontal, 16)
                    switch scope {
                    case "Persone": peopleSection
                    case "Attività": activitySection
                    default: placesSection
                    }
                }.padding(.vertical, 18)
            }
            .scrollDismissesKeyboard(.interactively).background(RoamStyle.canvas)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Person.self) { PersonView(person: $0) }
            .sheet(item: $openedPlace) { PlaceSheet(place: $0) }
            .onChange(of: scope) { _, _ in appleResults = []; searchFailure = nil }
            .task(id: searchKey) {
                do { try await Task.sleep(for: .milliseconds(trimmed.isEmpty ? 0 : 350)); try Task.checkCancellation() } catch { return }
                await runSearch()
            }
        }
    }
    @ViewBuilder private var placesSection: some View {
        if location.coordinate == nil && store.knownPlaces.isEmpty {
            RoamEmptyState(icon: "location.magnifyingglass", title: "Dove ti trovi?", message: "Attiva la posizione per cercare luoghi e attrazioni vicino a te.", action: "Usa la mia posizione") { location.request() }.padding(.top, 24)
        } else {
            resultsHeader(trimmed.isEmpty ? "VICINO A TE" : "RISULTATI")
            placeList
            appleHint
        }
    }
    @ViewBuilder private var activitySection: some View {
        if let activity {
            HStack(spacing: 10) {
                Image(systemName: activity.icon).foregroundStyle(.white)
                Text(activity.title).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                Button { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { self.activity = nil; appleResults = [] } } label: {
                    Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(.white)
                }.accessibilityLabel("Scegli un’altra attività")
            }.padding(.horizontal, 16).padding(.vertical, 12).background(RoamStyle.red, in: Capsule()).padding(.horizontal, 24)
            resultsHeader("NEI DINTORNI")
            placeList
            appleHint
        } else if activities.isEmpty {
            RoamEmptyState(icon: "sparkle.magnifyingglass", title: "Nessuna attività trovata", message: "Prova con un’altra parola, ad esempio musei, pizza o parchi.").padding(.top, 24)
        } else {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(activities) { item in
                    Button { fieldFocused = false; query = ""; withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { activity = item } } label: {
                        VStack(alignment: .leading, spacing: 14) {
                            Image(systemName: item.icon).font(.title3).foregroundStyle(RoamStyle.red)
                                .frame(width: 44, height: 44).background(RoamStyle.red.opacity(0.08), in: Circle())
                            Text(item.title).font(.subheadline.bold()).foregroundStyle(.primary).multilineTextAlignment(.leading).lineLimit(2, reservesSpace: true)
                        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white, in: RoundedRectangle(cornerRadius: 22))
                            .shadow(color: .black.opacity(0.025), radius: 12, y: 5)
                    }.buttonStyle(DiscoveryPressStyle())
                }
            }.padding(.horizontal, 24)
        }
    }
    @ViewBuilder private var peopleSection: some View {
        if let peopleError {
            VStack(alignment: .leading, spacing: 10) {
                Label(peopleError, systemImage: "wifi.exclamationmark").font(.subheadline)
                Button("Riprova") { Task { await runSearch() } }
            }.padding().frame(maxWidth: .infinity, alignment: .leading).background(RoamStyle.surface, in: RoundedRectangle(cornerRadius: 20)).padding(.horizontal, 24)
        } else if people.isEmpty && peopleLoaded {
            RoamEmptyState(icon: "person.2", title: trimmed.isEmpty ? "Ancora nessun viaggiatore" : "Nessuno con questo nome", message: trimmed.isEmpty ? "Chi pubblica un’esperienza nel Feed apparirà qui." : "Controlla il nome o prova solo con l’iniziale.").padding(.top, 24)
        } else if !peopleLoaded {
            ProgressView().frame(maxWidth: .infinity).padding(40)
        } else {
            resultsHeader(trimmed.isEmpty ? "VIAGGIATORI ATTIVI" : "VIAGGIATORI")
            LazyVStack(spacing: 0) {
                ForEach(people) { person in
                    NavigationLink(value: person) { PersonRow(person: person) }.buttonStyle(.plain)
                    if person.id != people.last?.id { Divider().padding(.leading, 78) }
                }
            }.background(.white, in: RoundedRectangle(cornerRadius: 26)).padding(.horizontal, 24)
        }
    }
    private func resultsHeader(_ title: String) -> some View {
        HStack {
            Text(title).font(.system(size: 10, weight: .bold)).tracking(2).foregroundStyle(RoamStyle.red)
            Spacer()
            if searching || store.loading { ProgressView() }
        }.padding(.horizontal, 24)
    }
    @ViewBuilder private var placeList: some View {
        let results = Array(placeResults.prefix(60))
        if results.isEmpty && !searching {
            RoamEmptyState(icon: "mappin.slash", title: "Nessun luogo trovato", message: trimmed.isEmpty && activity == nil ? "Sposta la Mappa per caricare luoghi in un’altra zona." : "Prova un’altra ricerca o esplora la Mappa.").padding(.top, 16)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(results) { place in
                    Button { openedPlace = place } label: { SearchPlaceRow(place: place) }.buttonStyle(.plain)
                    if place.id != results.last?.id { Divider().padding(.leading, 78) }
                }
            }.background(.white, in: RoundedRectangle(cornerRadius: 26)).padding(.horizontal, 24)
        }
        if let searchFailure { Label(searchFailure, systemImage: "wifi.exclamationmark").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 24) }
    }
    @ViewBuilder private var appleHint: some View {
        if !store.appleSearchEnabled && location.coordinate != nil {
            VStack(alignment: .leading, spacing: 10) {
                Text("Cerca anche con Mappe Apple").font(.headline)
                Text("Per cercare oltre i luoghi già caricati, la ricerca invia ad Apple il testo e la tua zona. Puoi disattivarla nel profilo.").font(.caption).foregroundStyle(.secondary)
                Button("Attiva ricerca con Mappe Apple") { store.appleSearchEnabled = true }.buttonStyle(.borderedProminent)
            }.padding().background(RoamStyle.surface, in: RoundedRectangle(cornerRadius: 20)).padding(.horizontal, 24)
        }
    }
    private func runSearch() async {
        searchFailure = nil
        if scope == "Persone" {
            do { people = try await store.searchPeople(trimmed); peopleError = nil }
            catch { if !Task.isCancelled { peopleError = "Viaggiatori non disponibili. Controlla la connessione." } }
            if !Task.isCancelled { peopleLoaded = true }
            return
        }
        let text = scope == "Attività" ? activity?.query ?? "" : trimmed
        guard !text.isEmpty, store.appleSearchEnabled, let coordinate = location.coordinate else { appleResults = []; return }
        searching = true
        defer { searching = false }
        do {
            let found = try await store.searchPlaces(text, near: coordinate, category: scope == "Attività" ? activity?.category : nil)
            try Task.checkCancellation()
            appleResults = scope == "Attività" ? found.filter { $0.distance <= 20 } : found
        } catch { if !Task.isCancelled { appleResults = []; searchFailure = "Mappe Apple non risponde: mostro i luoghi già caricati." } }
    }
}
struct PersonView: View {
    let person: Person
    @EnvironmentObject private var store: Store
    @State private var loaded = false
    @State private var failure: String?
    @State private var commenting: SocialPost?
    @State private var openedPlace: Place?
    private var posts: [SocialPost] { store.personFeed.filter { $0.author == person.name } }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 18) {
                    if person.mine { Avatar(photo: store.profile.photo, size: 86) }
                    else {
                        Text(String(person.name.prefix(1)).uppercased()).font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(RoamStyle.red)
                            .frame(width: 86, height: 86).background(RoamStyle.red.opacity(0.08), in: Circle())
                    }
                    HStack(spacing: 0) {
                        counter(person.posts, "Post")
                        counter(person.places, "Luoghi")
                    }
                }.padding(16)
                Text(person.mine ? store.profile.name : person.name).font(.subheadline.bold()).padding(.horizontal, 16).padding(.bottom, 12)
                if let failure {
                    VStack(alignment: .leading, spacing: 10) { Text(failure).font(.subheadline); Button("Riprova") { Task { await load() } } }.padding(16)
                } else if !loaded { ProgressView().frame(maxWidth: .infinity).padding(40) }
                else if posts.isEmpty { RoamEmptyState(icon: "photo.on.rectangle.angled", title: "Nessuna esperienza", message: "Questo viaggiatore non ha ancora condiviso luoghi.").padding(.top, 24) }
                ForEach(posts) { post in
                    SocialPostCard(post: post, place: post.place, onPlace: { openedPlace = post.place }, onComment: { commenting = post })
                }
            }
        }
        .background(Color.white).navigationTitle(person.mine ? store.profile.name : person.name).roamHeader()
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $commenting) { SocialCommentsView(post: $0) }
        .sheet(item: $openedPlace) { PlaceSheet(place: $0) }
    }
    private func load() async {
        do { try await store.loadPersonFeed(person.name); failure = nil }
        catch { if !Task.isCancelled { failure = "Esperienze non disponibili. Riprova." } }
        loaded = true
    }
    private func counter(_ value: Int, _ title: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)").font(.headline)
            Text(title).font(.caption).foregroundStyle(.black)
        }.frame(maxWidth: .infinity).accessibilityElement(children: .combine)
    }
}
struct ChatView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var location: LocationService
    @AppStorage("shareLocation") private var shareLocation = true
    @State private var messages = [Message(text: "Ciao! Cerchi un’attrazione, un caffè o un negozio? Ti aiuto a esplorare: usa la chat per chiedere consigli e idee di viaggio.", user: false)]
    @State private var input = ""
    @State private var waiting = false
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if messages.count == 1 {
                    VStack(alignment: .leading, spacing: 18) {
                        RoamMark().stroke(RoamStyle.red, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)).frame(width: 54, height: 54)
                        Text("Partiamo da\nun’idea.").font(.system(.largeTitle, design: .rounded, weight: .bold)).tracking(-1.4)
                        Text("Un posto speciale, una pausa o un giro diverso. Chiedimi da dove iniziare.").font(.subheadline).foregroundStyle(.secondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(["Cosa vedere qui?", "Una pausa caffè", "Un giro tra i negozi"], id: \.self) { suggestion in
                                    Button { input = suggestion; send() } label: { Text(suggestion).font(.caption.bold()).padding(13).background(.white, in: Capsule()) }.buttonStyle(.plain).foregroundStyle(RoamStyle.red)
                                }
                            }
                        }
                    }.padding(24)
                } else {
                    Label(shareLocation ? location.status : "Posizione non condivisa", systemImage: "location").font(.caption).foregroundStyle(.secondary).padding(12)
                }
                ScrollViewReader { proxy in
                    ScrollView { LazyVStack(spacing: 16) { ForEach(messages) { message in HStack { if message.user { Spacer(minLength: 40) }; Text(message.text).textSelection(.enabled).foregroundStyle(message.user ? Color.white : Color.primary).padding(16).background(message.user ? RoamStyle.red : Color.white, in: RoundedRectangle(cornerRadius: 20)); if !message.user { Spacer(minLength: 40) } }.id(message.id).transition(.move(edge: .bottom).combined(with: .opacity)) }; if waiting { ProgressView("Sto cercando…") } }.padding() }
                        .onChange(of: messages.count) { _, _ in if let id = messages.last?.id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } } }
                }
                HStack { TextField("Chiedi qualcosa…", text: $input, axis: .vertical).lineLimit(1...4); Button { send() } label: { Image(systemName: "arrow.up.circle.fill").font(.largeTitle) }.disabled(waiting || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityLabel("Invia messaggio") }.padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28)).padding(.horizontal, 20).padding(.bottom, 12)
            }.scrollDismissesKeyboard(.interactively).background(RoamStyle.canvas).navigationTitle("Assistente").roamHeader()
        }
    }
    func send() {
        let text = input; input = ""; messages.append(.init(text: text, user: true)); waiting = true
        Task {
            defer { waiting = false }
            do {
                let c = shareLocation ? location.coordinate : nil
                var payload: [String: Any] = ["message": text]
                if let c {
                    payload["latitude"] = c.latitude; payload["longitude"] = c.longitude
                    payload["nearby_places"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Array(store.places.prefix(30))))
                }
                let data = try JSONSerialization.data(withJSONObject: payload)
                let reply: ChatReply = try await store.request("/chat", method: "POST", body: data)
                messages.append(.init(text: reply.reply, user: false))
            } catch { messages.append(.init(text: "Non riesco a contattare il server. Riprova tra poco.", user: false)) }
        }
    }
}
struct ProfileView: View {
    @EnvironmentObject var store: Store
    @State private var composing = false
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 18) {
                        Avatar(photo: store.profile.photo, size: 86)
                        HStack(spacing: 0) {
                            counter(store.stats.posts, "Post")
                            counter(store.stats.places, "Luoghi")
                            counter(store.stats.saved, "Salvati")
                        }
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(store.profile.name).font(.subheadline.bold())
                        if !store.profile.bio.isEmpty { Text(store.profile.bio).font(.subheadline) }
                    }
                    if let issue = store.accountError { Text(issue).font(.caption).foregroundStyle(.black) }
                    HStack(spacing: 8) {
                        NavigationLink { EditProfileView(profile: store.profile) } label: {
                            Text("Modifica profilo").foregroundStyle(.black).frame(maxWidth: .infinity).frame(height: 38)
                                .background(.white, in: Capsule()).overlay(Capsule().strokeBorder(.black, lineWidth: 1))
                        }
                        Button { composing = true } label: {
                            Text("Nuovo post").foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 38).background(RoamStyle.red, in: Capsule())
                        }
                    }.font(.subheadline.weight(.semibold)).buttonStyle(DiscoveryPressStyle())
                }.padding(16)
                Image(systemName: "square.grid.3x3").font(.title3).padding(.vertical, 10)
                    .overlay(alignment: .bottom) { Capsule().fill(RoamStyle.red).frame(width: 28, height: 2) }
                    .frame(maxWidth: .infinity).padding(.bottom, 4)
                    .accessibilityLabel("I tuoi post")
                if store.myPosts.isEmpty {
                    if let issue = store.myPostsError {
                        VStack(spacing: 10) { Text(issue).font(.subheadline); Button("Riprova") { Task { await store.loadMyPosts() } } }.padding(32)
                    } else if !store.myPostsLoaded { ProgressView().padding(40) }
                    else {
                        RoamEmptyState(icon: "camera", title: "Condividi il tuo primo luogo", message: "Le foto che pubblichi nel Feed appariranno qui, ognuna con il suo luogo.", action: "Pubblica un post") { composing = true }.padding(.top, 24)
                    }
                } else {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(store.myPosts) { post in
                            NavigationLink(value: post.id) { PostThumbnail(post: post) }.buttonStyle(.plain)
                        }
                    }
                }
            }
            .background(Color.white).navigationTitle(store.profile.name).roamHeader()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink { ProfileSettingsView() } label: { Image(systemName: "gearshape") }.accessibilityLabel("Impostazioni")
                }
            }
            .navigationDestination(for: String.self) { MyPostsView(startID: $0) }
            .task { await store.loadMyPosts() }
            .refreshable { await store.loadMyPosts(); if let stats: Stats = try? await store.request("/stats") { store.stats = stats } }
            .sheet(isPresented: $composing) { SocialComposer(places: store.knownPlaces) { _ in } }
        }
    }
    private func counter(_ value: Int, _ title: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)").font(.headline).contentTransition(.numericText())
            Text(title).font(.caption).foregroundStyle(.black)
        }.frame(maxWidth: .infinity).accessibilityElement(children: .combine)
    }
}

struct PostThumbnail: View {
    let post: SocialPost
    var body: some View {
        Color.clear.aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image = PostImageCache.image(post) { Image(uiImage: image).resizable().scaledToFill() }
                else { ZStack { Color.white; PlaceGlyph(category: post.place.category).frame(width: 28, height: 28).foregroundStyle(RoamStyle.red) }.overlay(Rectangle().strokeBorder(RoamStyle.red, lineWidth: 0.5)) }
            }
            .clipped().contentShape(Rectangle())
            .accessibilityLabel("Post su \(post.place.name)")
    }
}

// Opens at the tapped post and scrolls through all of the user's posts, like Instagram.
struct MyPostsView: View {
    let startID: String
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var commenting: SocialPost?
    @State private var openedPlace: Place?
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(store.myPosts) { post in
                        SocialPostCard(post: post, place: post.place, onPlace: { openedPlace = post.place }, onComment: { commenting = post }).id(post.id)
                    }
                }
            }.onAppear { proxy.scrollTo(startID, anchor: .top) }
        }
        .background(Color.white).navigationTitle("Post").roamHeader()
        .onChange(of: store.myPosts.isEmpty) { _, empty in if empty { dismiss() } }
        .sheet(item: $commenting) { SocialCommentsView(post: $0) }
        .sheet(item: $openedPlace) { PlaceSheet(place: $0) }
    }
}

struct ProfileSettingsView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var location: LocationService
    @AppStorage("shareLocation") private var shareLocation = true
    var body: some View {
        Form {
            Section {
                TravelDashboard(profile: store.profile, stats: store.stats)
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }
            Section("Privacy e posizione") {
                Toggle("Carica luoghi durante zoom e spostamenti", isOn: $store.viewportSearchEnabled)
                Text("La ricerca dell’area visibile invia l’area della mappa ad Apple e può includere luoghi oltre 5 km.").font(.caption).foregroundStyle(.secondary)
                Toggle("Ricerca con Mappe Apple", isOn: $store.appleSearchEnabled)
                    .onChange(of: store.appleSearchEnabled) { _, _ in Task { await store.loadPlaces(location.coordinate) } }
                Text("Quando è attiva, la ricerca invia la posizione ad Apple per trovare luoghi vicini.").font(.caption).foregroundStyle(.secondary)
                Toggle("Condividi posizione con la chat", isOn: $shareLocation)
                Button("Aggiorna la mia posizione") { location.request() }
                if location.permissionDenied { Button("Apri Impostazioni posizione") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } } }
                Text("La posizione si aggiorna quando usi l’app. I luoghi sono forniti da OpenStreetMap tramite Overpass e il server; il meteo da Open-Meteo. La condivisione chat invia la posizione anche all’assistente configurato.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Connessione al backend") {
                if let issue = store.accountError { Text(issue).font(.caption).foregroundStyle(.secondary) }
                TextField("URL API", text: $store.apiURL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Riconnetti e aggiorna") { Task { await store.load(location.coordinate); await store.loadMyPosts() } }
                Text("Demo personale senza account. Foto, post e commenti sono conservati sul server configurato.").font(.caption).foregroundStyle(.secondary)
            }
        }.scrollContentBackground(.hidden).background(RoamStyle.canvas).navigationTitle("Impostazioni").roamHeader()
    }
}

struct EditProfileView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Profile
    @State private var selection: PhotosPickerItem?
    @State private var saving = false
    @State private var loadingPhoto = false
    @State private var failure: String?
    init(profile: Profile) { _draft = State(initialValue: profile) }
    private var valid: Bool { !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draft.name.count <= 80 && draft.bio.count <= 500 }
    var body: some View {
        Form {
            Section {
                VStack(spacing: 16) {
                    Avatar(photo: draft.photo).scaleEffect(1.5).frame(height: 86)
                    PhotosPicker(selection: $selection, matching: .images) {
                        Label(loadingPhoto ? "Caricamento…" : "Scegli foto", systemImage: "camera")
                    }.disabled(saving || loadingPhoto)
                    if draft.photo != nil {
                        Button("Rimuovi foto", role: .destructive) { selection = nil; draft.photo = nil }.disabled(saving || loadingPhoto)
                    }
                }.frame(maxWidth: .infinity).padding(.vertical, 16)
            }
            Section {
                TextField("Come ti chiami?", text: $draft.name).textContentType(.name).disabled(saving)
            } header: { Text("Nome") } footer: { Text("Fino a 80 caratteri.") }
            Section {
                TextField("Racconta che esploratore sei…", text: $draft.bio, axis: .vertical).lineLimit(4...8).disabled(saving)
            } header: { Text("Bio") } footer: { Text("\(draft.bio.count)/500 caratteri").foregroundStyle(draft.bio.count > 500 ? Color.red : Color.secondary) }
            if let failure { Section { Text(failure).font(.subheadline).foregroundStyle(.red) } }
        }
        .scrollContentBackground(.hidden).background(RoamStyle.canvas)
        .navigationTitle("Modifica profilo").navigationBarBackButtonHidden(true).roamHeader()
        .interactiveDismissDisabled(saving || loadingPhoto)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() }.disabled(saving) }
            ToolbarItem(placement: .confirmationAction) {
                Button { save() } label: { if saving { ProgressView() } else { Text("Salva").bold() } }
                    .disabled(!valid || saving || loadingPhoto)
            }
        }
        .onChange(of: selection) { _, item in
            guard let item else { return }
            loadingPhoto = true; failure = nil
            Task {
                defer { loadingPhoto = false }
                do {
                    guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                        failure = "Non riesco a leggere questa immagine. Scegli un’altra foto."; return
                    }
                    let ratio = min(1, 600 / max(image.size.width, image.size.height))
                    let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
                    let resized = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
                    guard let jpeg = resized.jpegData(compressionQuality: 0.7) else { return }
                    draft.photo = jpeg.base64EncodedString()
                } catch { failure = "Caricamento foto non riuscito. Riprova." }
            }
        }
    }
    private func save() {
        saving = true; failure = nil
        var value = draft
        value.name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            defer { saving = false }
            do {
                let profile: Profile = try await store.request("/profile", method: "PUT", body: JSONEncoder().encode(value))
                store.profile = profile
                dismiss()
            } catch { failure = "Non riesco a salvare il profilo. Controlla la connessione e riprova: le tue modifiche sono ancora qui." }
        }
    }
}
