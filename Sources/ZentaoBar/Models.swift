import Foundation

// MARK: - App Configuration

struct AppConfig: Codable, Equatable, Sendable {
    let baseURL: String
    let account: String
    let userID: Int?
}

// MARK: - Task Work (用于 UI 展示)

struct TaskWork: Identifiable, Equatable, Sendable {
    let id: Int
    let name: String
    let url: String
    var totalConsumed: Double

    var formattedConsumedWithUnit: String {
        if totalConsumed.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(totalConsumed))h"
        }

        return String(format: "%.1fh", totalConsumed)
    }
}

// MARK: - Load State

enum LoadState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case empty
    case authRequired
    case failed(String)
}

// MARK: - API Error

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

// MARK: - User

struct ZentaoUser: Codable, Sendable {
    let id: Int
    let account: String
    let realname: String
    let role: Role?
    let dept: Int
    let email: String?
    let mobile: String?
    let join: String?
    let admin: Bool

    struct Role: Codable, Sendable {
        let code: String
        let name: String
    }
}

// MARK: - Token Response

struct ZentaoTokenResponse: Codable, Sendable {
    let token: String
}

// MARK: - User Response

struct ZentaoUserResponse: Codable, Sendable {
    let profile: ZentaoProfile

    struct ZentaoProfile: Codable, Sendable {
        let id: Int
        let account: String
        let realname: String
        let role: ZentaoUser.Role?
        let dept: Int
        let email: String?
        let mobile: String?
        let join: String?
        let admin: Bool
    }
}

// MARK: - Task Item

struct ZentaoTaskItem: Codable, Identifiable, Sendable {
    let id: Int
    let name: String
    let project: Int
    let execution: Int
    let module: Int?
    let story: Int?
    let type: String?
    let pri: Int?
    let estimate: Double?
    let consumed: Double?
    let left: Double?
    let deadline: String?
    let status: String
    let assignedTo: String?
    let assignedToRealName: String?
    let openedBy: String?
    let openedDate: String?
    let assignedDate: String?
    let realStarted: String?
    let finishedBy: String?
    let finishedDate: String?
    let closedBy: String?
    let closedDate: String?
    let closedReason: String?
    let projectName: String?
    let executionName: String?
    let storyID: Int?
    let storyTitle: String?
    let progress: Double?
    let estimateLabel: String?
    let consumedLabel: String?
    let leftLabel: String?
    let desc: String?

    enum CodingKeys: String, CodingKey {
        case id, name, project, execution, module, story, type, pri
        case estimate, consumed, left, deadline, status
        case assignedTo = "assignedTo"
        case assignedToRealName, openedBy, openedDate, assignedDate, realStarted
        case finishedBy, finishedDate, closedBy, closedDate, closedReason
        case projectName, executionName, storyID = "storyID", storyTitle
        case progress, estimateLabel, consumedLabel, leftLabel, desc
    }
}

// MARK: - Task List Response (外层)

struct ZentaoTaskListResponse: Codable, Sendable {
    let status: String
    let data: String
    let md5: String?
}

// MARK: - Task List Data (内层，二次解析)

struct ZentaoTaskListData: Codable, Sendable {
    let title: String?
    let type: String?
    let tasks: [ZentaoTaskItem]
    let summary: String?
    let pager: ZentaoPager?

    enum CodingKeys: String, CodingKey {
        case title, type, tasks, summary, pager
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        pager = try container.decodeIfPresent(ZentaoPager.self, forKey: .pager)

        // tasks 可能是数组，也可能是字典
        if let tasksArray = try? container.decode([ZentaoTaskItem].self, forKey: .tasks) {
            DebugLogger.log("ZentaoTaskListData: parsed tasks as array, count=\(tasksArray.count)")
            tasks = tasksArray
        } else if let tasksDict = try? container.decode([String: ZentaoTaskItem].self, forKey: .tasks) {
            DebugLogger.log("ZentaoTaskListData: parsed tasks as dict, count=\(tasksDict.count)")
            tasks = tasksDict.sorted { Int($0.key) ?? 0 < Int($1.key) ?? 0 }.map { $0.value }
        } else {
            // 尝试查看原始数据结构
            if let rawData = try? container.decode([String: Any].self, forKey: .tasks) {
                DebugLogger.log("ZentaoTaskListData: tasks field has unknown structure: \(rawData)")
            } else if let rawArray = try? container.decode([Any].self, forKey: .tasks) {
                DebugLogger.log("ZentaoTaskListData: tasks field is an array of unknown type: \(rawArray)")
            } else {
                DebugLogger.log("ZentaoTaskListData: tasks field is nil or empty")
            }
            tasks = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(type, forKey: .type)
        try container.encode(tasks, forKey: .tasks)
        try container.encodeIfPresent(summary, forKey: .summary)
        try container.encodeIfPresent(pager, forKey: .pager)
    }
}

// MARK: - Pager

struct ZentaoPager: Codable, Sendable {
    let recTotal: Int
    let recPerPage: Int
    let pageTotal: Int
    let pageID: Int
    let offset: Int

    enum CodingKeys: String, CodingKey {
        case recTotal
        case recPerPage
        case pageTotal
        case pageID
        case offset
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recTotal = try container.decode(Int.self, forKey: .recTotal)
        recPerPage = try container.decode(Int.self, forKey: .recPerPage)
        pageTotal = try container.decode(Int.self, forKey: .pageTotal)
        pageID = try container.decode(Int.self, forKey: .pageID)
        offset = try container.decode(Int.self, forKey: .offset)
    }
}

// MARK: - Task Detail Response

struct ZentaoTaskDetailResponse: Codable, Sendable {
    let status: String
    let data: String
    let md5: String?
}

// MARK: - Task Detail Data

struct ZentaoTaskDetailData: Codable, Sendable {
    let title: String?
    let task: ZentaoTaskItem?
    let execution: ZentaoExecution?
    let members: [String: String]?
    let users: [String: String]?
    let actions: [String: ZentaoTaskAction]?

    enum CodingKeys: String, CodingKey {
        case title, task, execution, members, users, actions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        task = try container.decodeIfPresent(ZentaoTaskItem.self, forKey: .task)
        execution = try container.decodeIfPresent(ZentaoExecution.self, forKey: .execution)
        members = try container.decodeIfPresent([String: String].self, forKey: .members)
        users = try container.decodeIfPresent([String: String].self, forKey: .users)
        actions = try container.decodeIfPresent([String: ZentaoTaskAction].self, forKey: .actions)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(task, forKey: .task)
        try container.encodeIfPresent(execution, forKey: .execution)
        try container.encodeIfPresent(members, forKey: .members)
        try container.encodeIfPresent(users, forKey: .users)
        try container.encodeIfPresent(actions, forKey: .actions)
    }

    func todayConsumed() -> Double {
        guard let actions else { return 0 }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        var total: Double = 0
        for (_, action) in actions where action.action == "recordworkhour" {
            if let actionDate = parseDate(action.date), calendar.isDate(actionDate, inSameDayAs: today) {
                if let hours = Double(action.extra ?? "") {
                    total += hours
                }
            }
        }
        return total
    }

    private func parseDate(_ dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: dateString)
    }
}

struct ZentaoTaskAction: Codable, Sendable {
    let id: Int
    let objectType: String?
    let objectID: Int
    let actor: String?
    let action: String
    let date: String
    let comment: String?
    let extra: String?

    enum CodingKeys: String, CodingKey {
        case id, objectType, objectID, actor, action, date, comment, extra
    }
}

// MARK: - Execution (用于任务详情)

struct ZentaoExecution: Codable, Sendable {
    let id: Int
    let project: Int
    let name: String
    let type: String?
    let status: String?
    let begin: String?
    let end: String?

    enum CodingKeys: String, CodingKey {
        case id, project, name, type, status, begin, end
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        project = try container.decode(Int.self, forKey: .project)
        name = try container.decode(String.self, forKey: .name)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        begin = try container.decodeIfPresent(String.self, forKey: .begin)
        end = try container.decodeIfPresent(String.self, forKey: .end)
    }
}

// MARK: - 今日动态

struct ZentaoDynamicResponse: Codable, Sendable {
    let status: String
    let data: String
    let md5: String?
}

struct ZentaoDynamicData: Codable, Sendable {
    let title: String?
    let recTotal: Int
    let dateGroups: [String: [ZentaoDynamicAction]]

    enum CodingKeys: String, CodingKey {
        case title, recTotal, dateGroups
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        recTotal = try container.decodeIfPresent(Int.self, forKey: .recTotal) ?? 0

        if let groups = try? container.decode([String: [ZentaoDynamicAction]].self, forKey: .dateGroups) {
            dateGroups = groups
        } else if let groups = try? container.decode([String: ZentaoDynamicAction].self, forKey: .dateGroups) {
            dateGroups = groups.mapValues { [$0] }
        } else {
            dateGroups = [:]
        }
    }

    var taskIDsWithActionToday: [Int] {
        var ids = Set<Int>()
        for (_, actions) in dateGroups {
            for action in actions where action.objectType == "task" {
                ids.insert(action.objectID)
            }
        }
        return Array(ids).sorted()
    }
}

struct ZentaoDynamicAction: Codable, Sendable {
    let id: Int
    let objectType: String
    let objectID: Int
    let product: String?
    let project: Int?
    let execution: Int?
    let actor: String?
    let action: String
    let date: String
    let comment: String?
    let extra: String?
    let originalDate: String?
    let actionLabel: String?
    let objectLabel: String?
    let major: Int?
    let objectName: String?
    let objectLink: String?
    let time: String?

    enum CodingKeys: String, CodingKey {
        case id, objectType, objectID, product, project, execution, actor, action, date
        case comment, extra, originalDate, actionLabel, objectLabel, major, objectName, objectLink, time
    }
}