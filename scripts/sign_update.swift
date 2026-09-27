// Assina o pacote que o próprio app instala nas atualizações.
//
// O app só instala um zip cuja assinatura Ed25519 confere com a chave pública compilada nele
// (UpdateFeed.publicKey). Assim, quem consegue publicar no repositório das releases ainda não
// consegue entregar código aos usuários sem a chave privada.
//
//   swift scripts/sign_update.swift --generate-keys <arquivo-da-chave-privada>
//       Grava uma chave privada nova (base64) no arquivo, com permissão 600, e imprime a chave
//       pública para colar em UpdateFeed.publicKey. A privada vai para o segredo UPDATE_SIGNING_KEY.
//
//   UPDATE_SIGNING_KEY=<base64> swift scripts/sign_update.swift <arquivo>
//       Imprime a assinatura do arquivo em base64.
import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let arguments = Array(CommandLine.arguments.dropFirst())

if arguments.first == "--generate-keys" {
    guard arguments.count == 2 else { fail("uso: sign_update.swift --generate-keys <arquivo-da-chave-privada>") }
    let path = arguments[1]
    guard !FileManager.default.fileExists(atPath: path) else { fail("\(path) já existe; uma chave nunca é sobrescrita") }
    let key = Curve25519.Signing.PrivateKey()
    let created = FileManager.default.createFile(
        atPath: path,
        contents: Data(key.rawRepresentation.base64EncodedString().utf8),
        attributes: [.posixPermissions: 0o600]
    )
    guard created else { fail("não foi possível gravar \(path)") }
    print(key.publicKey.rawRepresentation.base64EncodedString())
    exit(0)
}

guard arguments.count == 1 else { fail("uso: sign_update.swift <arquivo>") }
guard let encoded = ProcessInfo.processInfo.environment["UPDATE_SIGNING_KEY"],
    let raw = Data(base64Encoded: encoded.trimmingCharacters(in: .whitespacesAndNewlines)),
    let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw)
else { fail("UPDATE_SIGNING_KEY ausente ou inválida") }
guard let data = FileManager.default.contents(atPath: arguments[0]) else { fail("não foi possível ler \(arguments[0])") }
guard let signature = try? key.signature(for: data), key.publicKey.isValidSignature(signature, for: data) else {
    fail("a assinatura gerada não confere")
}
print(signature.base64EncodedString())
