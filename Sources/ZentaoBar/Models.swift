import Foundation

struct AppConfig: Codable, Equatable, Sendable {
    let baseURL: String
    let account: String
}

struct TaskWork: Identifiable, Equatable, Sendable {
    let id: Int
    let name: String
    let url: String
    var totalConsumed: Double
}

enum LoadState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case empty
    case authRequired
    case failed(String)
}

struct ZentaoTokenResponse: Decodable, Sendable {
    let token: String
}

struct ZentaoCurrentUser: Decodable, Sendable {
    let account: String
}

struct ZentaoTask: Decodable, Sendable {
    let id: Int
    let name: String
    let assignedTo: String?
    let execution: Int?
}

struct ZentaoProject: Decodable, Sendable {
    let id: Int
    let name: String
}

struct ZentaoExecution: Decodable, Sendable {
    let id: Int
    let name: String
}

struct ZentaoEstimate: Decodable, Sendable {
    let account: String
    let date: String
    let consumed: Double
    let work: String?

    enum CodingKeys: String, CodingKey {
        case account
        case date
        case consumed
        case work
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        account = try container.decode(String.self, forKey: .account)
        date = try container.decode(String.self, forKey: .date)
        work = try container.decodeIfPresent(String.self, forKey: .work)

        if let doubleValue = try? container.decode(Double.self, forKey: .consumed) {
            consumed = doubleValue
        } else if let intValue = try? container.decode(Int.self, forKey: .consumed) {
            consumed = Double(intValue)
        } else if let stringValue = try? container.decode(String.self, forKey: .consumed),
                  let doubleValue = Double(stringValue) {
            consumed = doubleValue
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .consumed,
                in: container,
                debugDescription: "Unable to decode consumed as a number."
            )
        }
    }
}

enum ZentaoAPIError: LocalizedError, Sendable {
    case invalidBaseURL
    case invalidResponse
    case unauthorized
    case requestFailed(statusCode: Int, message: String?)
    case message(String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "地址格式错误，请输入完整的禅道地址。"
        case .invalidResponse:
            return "接口返回数据格式异常。"
        case .unauthorized:
            return "登录已失效，请重新登录。"
        case let .requestFailed(statusCode, message):
            if let message, !message.isEmpty {
                return "请求失败（\(statusCode)）：\(message)"
            }

            return "请求失败（\(statusCode)）。"
        case let .message(message):
            return message
        }
    }
}
