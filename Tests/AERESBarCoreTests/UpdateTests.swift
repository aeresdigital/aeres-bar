import CryptoKit
import Foundation
import Testing
import os

@testable import AERESBarCore

private let feedURL = URL(fileURLWithPath: "/").appending(path: "unused")
private let publishedZip = "https://github.com/aeresdigital/aeres-bar-releases/releases/download/v1.0.42/AERES-Bar.zip"
private let sonoma = OperatingSystemVersion(majorVersion: 14, minorVersion: 6, patchVersion: 1)

private func manifest(build: Int = 42, signature: String = "", minimum: String? = "14.0", notes: String = "- Novidade") -> UpdateManifest {
    UpdateManifest(
        version: "1.0.\(build)",
        build: build,
        notes: notes,
        url: URL(string: publishedZip) ?? feedURL,
        signature: signature,
        minimumSystemVersion: minimum
    )
}

private func encoded(_ manifest: UpdateManifest) throws -> Data {
    try JSONEncoder().encode(manifest)
}

@Suite("Atualização: manifesto e feed")
struct UpdateFeedTests {
    @Test("Lê o update.json publicado")
    func decodesManifest() throws {
        let decoded = try JSONDecoder().decode(UpdateManifest.self, from: try Fixture.data("update.json"))
        #expect(decoded.version == "1.0.42")
        #expect(decoded.build == 42)
        #expect(decoded.url.absoluteString == publishedZip)
        #expect(decoded.minimumSystemVersion == "14.0")
        #expect(
            decoded.releaseNotes == [
                ReleaseNote(text: "Novidades", isHeading: true),
                ReleaseNote(text: "Atualização pelo próprio app", isHeading: false),
                ReleaseNote(text: "Provedores chineses", isHeading: false),
                ReleaseNote(text: "Correções", isHeading: true),
                ReleaseNote(text: "O painel não fecha ao clicar num anel", isHeading: false),
            ]
        )
    }

    @Test("Só é atualização um build mais novo que roda neste macOS")
    func newerAndSupported() {
        #expect(manifest(build: 42).isUpdate(over: 41, system: sonoma))
        #expect(!manifest(build: 42).isUpdate(over: 42, system: sonoma))
        #expect(!manifest(build: 42).isUpdate(over: 50, system: sonoma))
        #expect(!manifest(minimum: "15.0").isUpdate(over: 1, system: sonoma))
        #expect(manifest(minimum: "14.6").runs(on: sonoma))
        #expect(!manifest(minimum: "14.6.2").runs(on: sonoma))
        #expect(manifest(minimum: "13").runs(on: sonoma))
        #expect(manifest(minimum: nil).runs(on: sonoma))
    }

    @Test("Notas: tira marcas de Markdown e linhas vazias")
    func releaseNotes() {
        let notes = manifest(notes: "## Novidades\n\n* Um\n-  Dois \n\nTexto solto\n#\n").releaseNotes
        #expect(notes.map(\.text) == ["Novidades", "Um", "Dois", "Texto solto"])
        #expect(notes.map(\.isHeading) == [true, false, false, false])
    }

    @Test("Busca o manifesto no feed, com Accept e User-Agent")
    func fetchesLatest() async throws {
        let body = try encoded(manifest())
        let http = MockHTTPClient(status: 200, body: body)
        let feed = UpdateFeed(http: http)
        #expect(try await feed.latest() == manifest())
        let request = try #require(http.requests.first)
        #expect(request.url == UpdateFeed.manifestURL)
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("AERESBar/") == true)
        #expect(
            UpdateFeed.manifestURL.absoluteString
                == "https://github.com/aeresdigital/aeres-bar-releases/releases/latest/download/update.json")
    }

    @Test("Falhas do feed viram UpdateFailure")
    func feedFailures() async throws {
        await #expect(throws: UpdateFailure.http(404)) { try await UpdateFeed(http: MockHTTPClient(status: 404)).latest() }
        await #expect(throws: UpdateFailure.invalidManifest) {
            try await UpdateFeed(http: MockHTTPClient(status: 200, body: Data("<html>".utf8))).latest()
        }
        await #expect(throws: UpdateFailure.invalidManifest) {
            try await UpdateFeed(http: MockHTTPClient(status: 200, body: try encoded(manifest(build: 0)))).latest()
        }
        await #expect(throws: UpdateFailure.unreachable(TestError.offline.localizedDescription)) {
            try await UpdateFeed(http: MockHTTPClient { _ in throw TestError.offline }).latest()
        }
        await #expect(throws: CancellationError.self) {
            try await UpdateFeed(http: MockHTTPClient { _ in throw URLError(.cancelled) }).latest()
        }
    }

    @Test("O zip precisa vir de onde está o feed")
    func zipFromTheFeedOnly() async throws {
        var elsewhere = manifest()
        elsewhere.url = try #require(URL(string: "https://example.com/AERES-Bar.zip"))
        let feed = UpdateFeed(http: MockHTTPClient(status: 200, body: try encoded(elsewhere)))
        await #expect(throws: UpdateFailure.invalidManifest) { try await feed.latest() }

        let local = try #require(URL(string: "http://127.0.0.1:8765/update.json"))
        #expect(UpdateFeed.sameOrigin(try #require(URL(string: "http://127.0.0.1:8765/AERES-Bar.zip")), local))
        #expect(!UpdateFeed.sameOrigin(try #require(URL(string: "http://127.0.0.1:9999/AERES-Bar.zip")), local))
        #expect(!UpdateFeed.sameOrigin(try #require(URL(string: "https://127.0.0.1:8765/AERES-Bar.zip")), local))
    }

    @Test("Baixa o zip do manifesto")
    func downloads() async throws {
        let http = MockHTTPClient { request in
            HTTPResponse(status: request.url?.absoluteString == publishedZip ? 200 : 404, body: Data("zip".utf8))
        }
        #expect(try await UpdateFeed(http: http).download(manifest()) == Data("zip".utf8))
        #expect(http.requests.first?.value(forHTTPHeaderField: "Accept") == "application/octet-stream")
        await #expect(throws: UpdateFailure.http(500)) { try await UpdateFeed(http: MockHTTPClient(status: 500)).download(manifest()) }
    }

    @Test("Feed de teste definido nas preferências")
    func feedOverride() throws {
        let suite = "AERESBarUpdateTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(UpdateFeed.configuredManifestURL(defaults: defaults) == UpdateFeed.manifestURL)
        defaults.set("sem esquema", forKey: UpdateFeed.overrideKey)
        #expect(UpdateFeed.configuredManifestURL(defaults: defaults) == UpdateFeed.manifestURL)
        defaults.set("http://127.0.0.1:8765/update.json", forKey: UpdateFeed.overrideKey)
        #expect(UpdateFeed.configuredManifestURL(defaults: defaults).absoluteString == "http://127.0.0.1:8765/update.json")
    }

    @Test("Assinatura Ed25519 do zip")
    func signature() throws {
        let key = Curve25519.Signing.PrivateKey()
        let publicKey = key.publicKey.rawRepresentation.base64EncodedString()
        let zip = Data("conteúdo do zip".utf8)
        let signature = try key.signature(for: zip).base64EncodedString()
        #expect(UpdateSignature.isValid(signature, for: zip, publicKey: publicKey))
        #expect(!UpdateSignature.isValid(signature, for: zip + Data([0]), publicKey: publicKey))
        #expect(!UpdateSignature.isValid(signature, for: zip))  // the published key did not sign it
        #expect(!UpdateSignature.isValid("não é base64", for: zip, publicKey: publicKey))
        #expect(!UpdateSignature.isValid(signature, for: zip, publicKey: "curta"))
        #expect(Data(base64Encoded: UpdateFeed.publicKey)?.count == 32)
    }
}

// MARK: - Installer

/// A minimal app: Info.plist and an executable script, signed ad hoc like the real one.
private func makeApp(in folder: URL, identifier: String = AppInfo.bundleIdentifier, build: Int, signed: Bool = true) throws -> URL {
    let app = folder.appendingPathComponent("AERES Bar.app")
    let macOS = app.appendingPathComponent("Contents/MacOS")
    try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
    let info: [String: Any] = [
        "CFBundleIdentifier": identifier, "CFBundleExecutable": "AERESBar", "CFBundleVersion": String(build),
        "CFBundleShortVersionString": "1.0.\(build)",
    ]
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        .write(to: app.appendingPathComponent("Contents/Info.plist"))
    let executable = macOS.appendingPathComponent("AERESBar")
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    if signed {
        let result = ProcessCommandRunner().run("/usr/bin/codesign", ["--force", "--sign", "-", app.path], timeout: 60)
        try #require(result?.status == 0, "codesign ad hoc")
    }
    return app
}

private func zip(_ items: [URL], in folder: URL) throws -> Data {
    let staging = folder.appendingPathComponent("staging-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
    for (index, item) in items.enumerated() {
        let name = index == 0 ? item.lastPathComponent : "Outro \(index).app"
        try FileManager.default.copyItem(at: item, to: staging.appendingPathComponent(name))
    }
    let archive = folder.appendingPathComponent("update-\(UUID().uuidString).zip")
    let result = ProcessCommandRunner().run("/usr/bin/ditto", ["-c", "-k", staging.path, archive.path], timeout: 60)
    try #require(result?.status == 0, "ditto")
    return try Data(contentsOf: archive)
}

private func version(of app: URL) -> String? {
    let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
    return info?["CFBundleVersion"] as? String
}

/// Polls until `condition` holds, for up to `seconds`.
private func eventually(within seconds: Double = 10, _ condition: @Sendable () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(50))
    }
    return condition()
}

/// A process that has already exited, so the swap does not wait.
private func exitedProcessID() throws -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
    try process.run()
    process.waitUntilExit()
    return process.processIdentifier
}

@Suite("Atualização: instalação")
struct UpdateInstallerTests {
    private func installer(for app: URL, build: Int = 41, marker: URL, processID: Int32 = 1) -> BundleUpdateInstaller {
        BundleUpdateInstaller(bundleURL: app, currentBuild: build, failureMarker: marker, processID: processID, reopensApp: false)
    }

    @Test("O app instalado numa pasta gravável pode ser substituído")
    func writableTarget() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let app = try makeApp(in: folder.url, build: 41)
        let target = try await installer(for: app, marker: folder.url.appendingPathComponent("failed")).installTarget()
        #expect(target == app.resolvingSymlinksInPath())
        #expect(!FileManager.default.fileExists(atPath: app.appendingPathComponent("Contents/.update-probe").path))
    }

    @Test("Cópia temporária do Gatekeeper, pasta sem permissão e app protegido")
    func unreplaceableTargets() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let marker = folder.url.appendingPathComponent("failed")

        let translocated = folder.url.appendingPathComponent("AppTranslocation/ABC")
        try FileManager.default.createDirectory(at: translocated, withIntermediateDirectories: true)
        let moved = try makeApp(in: translocated, build: 41, signed: false)
        await #expect(throws: UpdateFailure.translocated) { try await installer(for: moved, marker: marker).installTarget() }

        let locked = folder.url.appendingPathComponent("Somente leitura")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        let inLocked = try makeApp(in: locked, build: 41, signed: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        await #expect(throws: UpdateFailure.notWritable(locked.resolvingSymlinksInPath().path)) {
            try await installer(for: inLocked, marker: marker).installTarget()
        }

        let protected = try makeApp(in: folder.url, build: 41, signed: false)
        let contents = protected.appendingPathComponent("Contents")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: contents.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: contents.path) }
        await #expect(throws: UpdateFailure.protectedByMacOS) { try await installer(for: protected, marker: marker).installTarget() }
    }

    @Test("Descompacta ao lado do app e confere identificador, build e assinatura de código")
    func preparesValidUpdate() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let installed = try makeApp(in: folder.url.appendingPathComponent("Applications"), build: 41)
        let newer = try makeApp(in: folder.url.appendingPathComponent("build"), build: 42)
        let update = try await installer(for: installed, marker: folder.url.appendingPathComponent("failed"))
            .prepare(try zip([newer], in: folder.url), for: manifest(build: 42), replacing: installed)
        defer { try? FileManager.default.removeItem(at: update.workFolder) }
        #expect(update.target == installed)
        #expect(update.app.lastPathComponent == "AERES Bar.app")
        #expect(update.app.path.hasPrefix(update.workFolder.path))
        #expect(version(of: update.app) == "42")
        #expect(!FileManager.default.fileExists(atPath: update.workFolder.appendingPathComponent("update.zip").path))
    }

    @Test("Recusa pacotes inválidos, de outro app, antigos ou adulterados")
    func rejectsBadPackages() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let installed = try makeApp(in: folder.url.appendingPathComponent("Applications"), build: 41)
        let subject = installer(for: installed, marker: folder.url.appendingPathComponent("failed"))
        func build(_ name: String, identifier: String = AppInfo.bundleIdentifier, build: Int) throws -> URL {
            try makeApp(in: folder.url.appendingPathComponent(name), identifier: identifier, build: build)
        }

        await #expect(throws: UpdateFailure.invalidPackage) {
            try await subject.prepare(Data("não é zip".utf8), for: manifest(build: 42), replacing: installed)
        }
        let other = try build("outro", identifier: "com.example.other", build: 42)
        await #expect(throws: UpdateFailure.invalidPackage) {
            try await subject.prepare(try zip([other], in: folder.url), for: manifest(build: 42), replacing: installed)
        }
        let mismatched = try build("errado", build: 43)
        await #expect(throws: UpdateFailure.invalidPackage) {
            try await subject.prepare(try zip([mismatched], in: folder.url), for: manifest(build: 42), replacing: installed)
        }
        let older = try build("antigo", build: 41)
        await #expect(throws: UpdateFailure.notNewer) {
            try await subject.prepare(try zip([older], in: folder.url), for: manifest(build: 41), replacing: installed)
        }
        let twice = try build("dois", build: 42)
        await #expect(throws: UpdateFailure.invalidPackage) {
            try await subject.prepare(try zip([twice, twice], in: folder.url), for: manifest(build: 42), replacing: installed)
        }
        let tampered = try build("adulterado", build: 42)
        try Data("#!/bin/sh\necho outro\n".utf8).write(to: tampered.appendingPathComponent("Contents/MacOS/AERESBar"))
        await #expect(throws: UpdateFailure.invalidPackage) {
            try await subject.prepare(try zip([tampered], in: folder.url), for: manifest(build: 42), replacing: installed)
        }
    }

    @Test("O ajudante espera o app fechar, troca os apps e apaga a pasta de trabalho")
    func swapsAfterExit() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let installed = try makeApp(in: folder.url.appendingPathComponent("Applications"), build: 41)
        let newer = try makeApp(in: folder.url.appendingPathComponent("build"), build: 42)
        let marker = folder.url.appendingPathComponent("Support/failed")
        let package = try zip([newer], in: folder.url)

        // Stands in for the app, which quits a moment after the helper starts.
        let running = Process()
        running.executableURL = URL(fileURLWithPath: "/bin/sleep")
        running.arguments = ["1.5"]
        try running.run()
        let subject = installer(for: installed, marker: marker, processID: running.processIdentifier)
        let update = try await subject.prepare(package, for: manifest(build: 42), replacing: installed)
        try await subject.launch(update)

        #expect(version(of: installed) == "41", "trocou antes de o app fechar")
        #expect(await eventually { !FileManager.default.fileExists(atPath: update.workFolder.path) })
        #expect(version(of: installed) == "42")
        #expect(ProcessCommandRunner().run("/usr/bin/codesign", ["--verify", "--strict", installed.path], timeout: 60)?.status == 0)
        #expect(!FileManager.default.fileExists(atPath: marker.path))
        #expect(await subject.consumeFailedSwap() == false)
    }

    @Test("Se a troca falha, o app anterior volta e fica um aviso para a próxima abertura")
    func failedSwapKeepsOldApp() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let installed = try makeApp(in: folder.url.appendingPathComponent("Applications"), build: 41)
        let work = folder.url.appendingPathComponent("work")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let script = try folder.write(BundleUpdateInstaller.swapScript, to: "swap.sh")
        let marker = folder.url.appendingPathComponent("failed")
        let missing = work.appendingPathComponent("não existe.app")

        let result = ProcessCommandRunner().run(
            "/bin/sh", [script.path, String(try exitedProcessID()), missing.path, installed.path, work.path, marker.path, "0"], timeout: 30)
        #expect(result?.status == 0)
        #expect(version(of: installed) == "41")
        #expect(FileManager.default.fileExists(atPath: marker.path))
        #expect(!FileManager.default.fileExists(atPath: work.path))

        let subject = installer(for: installed, marker: marker)
        #expect(await subject.consumeFailedSwap())
        #expect(await subject.consumeFailedSwap() == false)
    }
}

// MARK: - Updater

/// Serves a manifest and a zip, or fails, and counts the calls.
private final class FakeUpdateSource: UpdateSource {
    private struct State {
        var latest: Result<UpdateManifest, UpdateFailure>
        var zip: Result<Data, UpdateFailure>
        var downloadDelay: Duration = .zero
        var checks = 0
        var downloads = 0
    }

    private let state: OSAllocatedUnfairLock<State>

    init(latest: Result<UpdateManifest, UpdateFailure>, zip: Result<Data, UpdateFailure> = .success(Data("zip".utf8))) {
        state = OSAllocatedUnfairLock(initialState: State(latest: latest, zip: zip))
    }

    var checks: Int { state.withLock { $0.checks } }
    var downloads: Int { state.withLock { $0.downloads } }

    func slowDownloads() {
        state.withLock { $0.downloadDelay = .seconds(30) }
    }

    func latest() async throws -> UpdateManifest {
        try state.withLock { state in
            state.checks += 1
            return state.latest
        }.get()
    }

    func download(_ manifest: UpdateManifest) async throws -> Data {
        let (zip, delay) = state.withLock { state in
            state.downloads += 1
            return (state.zip, state.downloadDelay)
        }
        if delay > .zero { try await Task.sleep(for: delay) }
        return try zip.get()
    }
}

/// Records what the updater asks for; each step can be made to fail.
private actor FakeUpdateInstaller: UpdateInstalling {
    var targetFailure: UpdateFailure?
    var prepareFailure: UpdateFailure?
    var failedSwap = false
    private(set) var prepared: [UpdateManifest] = []
    private(set) var launched: [PreparedUpdate] = []

    func fail(target: UpdateFailure? = nil, prepare: UpdateFailure? = nil) {
        targetFailure = target
        prepareFailure = prepare
    }

    func leaveFailedSwap() {
        failedSwap = true
    }

    func installTarget() throws -> URL {
        if let targetFailure { throw targetFailure }
        return URL(fileURLWithPath: "/Applications/AERES Bar.app")
    }

    func prepare(_ zip: Data, for manifest: UpdateManifest, replacing target: URL) throws -> PreparedUpdate {
        if let prepareFailure { throw prepareFailure }
        prepared.append(manifest)
        return PreparedUpdate(
            app: URL(fileURLWithPath: "/tmp/work/new/AERES Bar.app"), target: target, workFolder: URL(fileURLWithPath: "/tmp/work"))
    }

    func launch(_ update: PreparedUpdate) {
        launched.append(update)
    }

    func consumeFailedSwap() -> Bool {
        defer { failedSwap = false }
        return failedSwap
    }
}

@Suite("Atualização: estados do atualizador")
@MainActor
struct AppUpdaterTests {
    private let key = Curve25519.Signing.PrivateKey()

    private func signed(build: Int = 42) throws -> UpdateManifest {
        manifest(build: build, signature: try key.signature(for: Data("zip".utf8)).base64EncodedString())
    }

    private func updater(
        _ source: FakeUpdateSource,
        _ installer: FakeUpdateInstaller = FakeUpdateInstaller(),
        enabled: Bool = true,
        quit: @escaping @MainActor () -> Void = {}
    ) -> AppUpdater {
        AppUpdater(
            source: source,
            installer: installer,
            currentVersion: "1.0.41",
            currentBuild: 41,
            isEnabled: enabled,
            system: sonoma,
            publicKey: key.publicKey.rawRepresentation.base64EncodedString(),
            quit: quit
        )
    }

    @Test("Fora do app instalado não procura nada")
    func disabled() async throws {
        let source = FakeUpdateSource(latest: .success(try signed()))
        let subject = updater(source, enabled: false)
        #expect(await subject.check(userInitiated: true) == .failed(.developmentBuild))
        subject.start(after: .zero)
        #expect(subject.phase == .idle)
        #expect(source.checks == 0)
    }

    @Test("Procurar: versão nova, nenhuma ou falha")
    func userChecks() async throws {
        let update = try signed()
        let subject = updater(FakeUpdateSource(latest: .success(update)))
        #expect(await subject.check(userInitiated: true) == .available(update))
        #expect(subject.phase == .available(update))
        #expect(subject.pendingUpdate == update)

        let current = updater(FakeUpdateSource(latest: .success(try signed(build: 41))))
        #expect(await current.check(userInitiated: true) == .upToDate)
        #expect(current.phase == .idle)

        let offline = updater(FakeUpdateSource(latest: .failure(.unreachable("sem rede"))))
        #expect(await offline.check(userInitiated: true) == .failed(.unreachable("sem rede")))
        #expect(offline.phase == .idle)
    }

    @Test("\"Agora não\" silencia as verificações automáticas até a próxima abertura")
    func postpone() async throws {
        let update = try signed()
        let subject = updater(FakeUpdateSource(latest: .success(update)))
        await subject.check(userInitiated: false)
        #expect(subject.phase == .available(update))
        subject.dismiss()
        #expect(subject.phase == .idle)
        #expect(await subject.check(userInitiated: false) == .available(update))
        #expect(subject.phase == .idle)
        await subject.check(userInitiated: true)
        #expect(subject.phase == .available(update))
    }

    @Test("Instala: baixa, confere a assinatura, prepara, chama o ajudante e fecha o app")
    func installs() async throws {
        let update = try signed()
        let source = FakeUpdateSource(latest: .success(update))
        let installer = FakeUpdateInstaller()
        var quits = 0
        let subject = updater(source, installer) { quits += 1 }
        await subject.check(userInitiated: false)
        await subject.install()?.value
        #expect(subject.phase == .installing(update))
        #expect(await installer.prepared == [update])
        #expect(await installer.launched.count == 1)
        #expect(quits == 1)
        #expect(subject.isBusy)
        #expect(await subject.check(userInitiated: true) == .busy)
    }

    @Test("Assinatura errada: nada é instalado")
    func badSignature() async throws {
        var update = try signed()
        update.signature = try Curve25519.Signing.PrivateKey().signature(for: Data("zip".utf8)).base64EncodedString()
        let installer = FakeUpdateInstaller()
        var quits = 0
        let subject = updater(FakeUpdateSource(latest: .success(update)), installer) { quits += 1 }
        await subject.check(userInitiated: true)
        await subject.install()?.value
        #expect(subject.phase == .failed(.badSignature, update))
        #expect(await installer.prepared.isEmpty)
        #expect(quits == 0)
    }

    @Test("App protegido pelo macOS: nem baixa, e pede a reinstalação pelo Terminal")
    func protectedApp() async throws {
        let update = try signed()
        let source = FakeUpdateSource(latest: .success(update))
        let installer = FakeUpdateInstaller()
        await installer.fail(target: .protectedByMacOS)
        let subject = updater(source, installer)
        await subject.check(userInitiated: true)
        await subject.install()?.value
        #expect(subject.phase == .failed(.protectedByMacOS, update))
        #expect(UpdateFailure.protectedByMacOS.needsReinstall)
        #expect(source.downloads == 0)

        // A failure stays until closed; automatic checks do not replace it.
        await subject.check(userInitiated: false)
        #expect(subject.phase == .failed(.protectedByMacOS, update))
        subject.dismiss()
        #expect(subject.phase == .idle)
    }

    @Test("Falhas ao baixar ou preparar deixam tentar de novo")
    func retry() async throws {
        let update = try signed()
        let installer = FakeUpdateInstaller()
        await installer.fail(prepare: .invalidPackage)
        let subject = updater(FakeUpdateSource(latest: .success(update)), installer)
        await subject.check(userInitiated: true)
        await subject.install()?.value
        #expect(subject.phase == .failed(.invalidPackage, update))

        await installer.fail()
        await subject.install()?.value
        #expect(subject.phase == .installing(update))

        let download = updater(FakeUpdateSource(latest: .success(update), zip: .failure(.http(503))))
        await download.check(userInitiated: true)
        await download.install()?.value
        #expect(download.phase == .failed(.http(503), update))
    }

    @Test("Cancelar o download mantém a versão oferecida")
    func cancelDownload() async throws {
        let update = try signed()
        let source = FakeUpdateSource(latest: .success(update))
        source.slowDownloads()
        let subject = updater(source)
        await subject.check(userInitiated: true)
        let task = subject.install()
        #expect(subject.install() == task, "um segundo pedido reaproveita o que está em andamento")
        #expect(await eventually { source.downloads == 1 })
        #expect(subject.phase == .downloading(update))
        subject.cancel()
        await task?.value
        #expect(subject.phase == .available(update))
    }

    @Test("Ao iniciar, avisa da troca que falhou e procura de tempos em tempos")
    func startsChecking() async throws {
        let source = FakeUpdateSource(latest: .success(try signed()))
        let installer = FakeUpdateInstaller()
        await installer.leaveFailedSwap()
        let subject = updater(source, installer)
        subject.start(after: .zero, every: .milliseconds(50))
        subject.start(after: .zero)
        #expect(await eventually { source.checks >= 2 })
        subject.stop()
        #expect(subject.phase == .failed(.swapFailed, nil))
        #expect(UpdatePresentation.menuTitle(for: subject.phase) == nil)
        subject.dismiss()
        #expect(subject.phase == .idle)
    }

    @Test("Uma versão mais nova substitui a oferecida; o feed voltar atrás tira a oferta")
    func automaticChecksFollowTheFeed() async throws {
        let first = try signed(build: 42)
        let source = FakeUpdateSource(latest: .success(first))
        let subject = updater(source)
        await subject.check(userInitiated: false)
        #expect(subject.phase == .available(first))

        let newer = try signed(build: 43)
        let second = FakeUpdateSource(latest: .success(newer))
        let follow = updater(second)
        await follow.check(userInitiated: false)
        #expect(follow.phase == .available(newer))

        let gone = updater(FakeUpdateSource(latest: .success(try signed(build: 41))))
        await gone.check(userInitiated: true)
        #expect(gone.phase == .idle)
    }
}

// MARK: - Presentation

@Suite("Atualização: textos")
struct UpdatePresentationTests {
    private let update = manifest(notes: "### Novidades\n\n- Atualização pelo próprio app\n\n### Correções\n\n- Um\n")

    @Test("Item do menu")
    func menu() {
        #expect(UpdatePresentation.menuTitle(for: .idle) == nil)
        #expect(UpdatePresentation.menuTitle(for: .checking) == nil)
        #expect(UpdatePresentation.menuTitle(for: .available(update)) == "Instalar a versão 1.0.42…")
        #expect(UpdatePresentation.menuTitle(for: .failed(.badSignature, update)) == "Instalar a versão 1.0.42…")
        #expect(UpdatePresentation.menuTitle(for: .failed(.swapFailed, nil)) == nil)
        #expect(UpdatePresentation.menuTitle(for: .downloading(update)) == "Baixando a versão 1.0.42…")
        #expect(UpdatePresentation.menuTitle(for: .installing(update)) == "Instalando a versão 1.0.42…")
    }

    @Test("Aviso no painel")
    func notice() throws {
        #expect(UpdatePresentation.notice(for: .idle, currentVersion: "1.0.41") == nil)
        let available = try #require(UpdatePresentation.notice(for: .available(update), currentVersion: "1.0.41"))
        #expect(available.title == "Nova versão disponível: 1.0.42")
        #expect(available.detail == "Atualização pelo próprio app")
        #expect(!available.isProblem)
        let bare = try #require(UpdatePresentation.notice(for: .available(manifest(notes: "")), currentVersion: "1.0.41"))
        #expect(bare.detail == "Você tem a 1.0.41.")
        #expect(UpdatePresentation.notice(for: .downloading(update), currentVersion: "1.0.41")?.title == "Baixando a versão 1.0.42…")
        #expect(UpdatePresentation.notice(for: .installing(update), currentVersion: "1.0.41")?.detail.contains("abre de novo") == true)
        let failed = try #require(UpdatePresentation.notice(for: .failed(.badSignature, update), currentVersion: "1.0.41"))
        #expect(failed.isProblem)
        #expect(failed.detail == UpdateFailure.badSignature.message)
    }

    @Test("Respostas do Procurar atualizações")
    func checkMessages() {
        #expect(
            UpdatePresentation.checkMessage(for: .upToDate, currentVersion: "1.0.41").body == "Você já tem a versão mais recente (1.0.41).")
        #expect(UpdatePresentation.checkMessage(for: .failed(.http(404)), currentVersion: "1.0.41").body.contains("HTTP 404"))
        #expect(UpdatePresentation.checkMessage(for: .busy, currentVersion: "1.0.41").title == "Atualização em andamento")
        let offer = UpdatePresentation.checkMessage(for: .available(update), currentVersion: "1.0.41")
        #expect(offer.title == "Nova versão do AERES Bar: 1.0.42")
        #expect(offer.body.hasPrefix("Você tem a 1.0.41."))
        #expect(offer.body.contains("Novidades:\n• Atualização pelo próprio app"))
        #expect(offer.body.hasSuffix("O AERES Bar fecha e abre de novo em alguns segundos."))
    }

    @Test("Notas longas são cortadas no diálogo")
    func longNotes() {
        let many = manifest(notes: (1...20).map { "- Item \($0)" }.joined(separator: "\n"))
        let body = UpdatePresentation.confirmation(for: many, currentVersion: "1.0.41").body
        #expect(body.contains("• Item \(UpdatePresentation.noteLimit)"))
        #expect(!body.contains("• Item \(UpdatePresentation.noteLimit + 1)"))
        #expect(body.contains("\n…"))
    }

    @Test("Toda falha tem uma mensagem; só as que a reinstalação resolve mostram o comando")
    func failures() {
        let all: [UpdateFailure] = [
            .unreachable("x"), .http(404), .http(500), .invalidManifest, .badSignature, .invalidPackage, .notNewer, .translocated,
            .notWritable("/Applications"), .protectedByMacOS, .swapFailed, .developmentBuild, .other("disco cheio"),
        ]
        #expect(all.allSatisfy { !$0.message.isEmpty })
        #expect(all.filter(\.needsReinstall) == [.protectedByMacOS, .swapFailed])
        #expect(UpdateFailure.notWritable("/Applications").message.contains("/Applications"))
        #expect(UpdateFeed.installCommand.hasPrefix("curl -fsSL https://github.com/aeresdigital/aeres-bar-releases/"))
    }
}
