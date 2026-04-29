import Foundation

struct ZentaoAPIClient: Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func normalizedBaseURL(from rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        if components.path.hasSuffix("/api.php/v1") {
            return nil
        }

        var path = components.path
        while path.hasSuffix("/") && path.count > 1 {
            path.removeLast()
        }
        components.path = path

        return components.url?.absoluteString
    }

    func fetchToken(baseURL: String, account: String, password: String) async throws -> String {
        DebugLogger.log("Requesting token for account=\(account), baseURL=\(baseURL)")
        let payload = try JSONSerialization.data(
            withJSONObject: [
                "account": account,
                "password": password
            ]
        )

        let data = try await request(
            baseURL: baseURL,
            path: "/api.php/v1/tokens",
            method: "POST",
            body: payload
        )

        if let response = try? JSONDecoder().decode(ZentaoTokenResponse.self, from: data) {
            DebugLogger.log("Token obtained successfully")
            return response.token
        }

        DebugLogger.log("Failed to parse token response")
        throw ZentaoAPIError.invalidResponse
    }

    func fetchCurrentUser(baseURL: String, token: String) async throws -> ZentaoUser {
        let data = try await request(
            baseURL: baseURL,
            path: "/api.php/v1/user",
            token: token
        )

        if let response = try? JSONDecoder().decode(ZentaoUserResponse.self, from: data) {
            return ZentaoUser(
                id: response.profile.id,
                account: response.profile.account,
                realname: response.profile.realname,
                role: response.profile.role,
                dept: response.profile.dept,
                email: response.profile.email,
                mobile: response.profile.mobile,
                join: response.profile.join,
                admin: response.profile.admin
            )
        }

        throw ZentaoAPIError.invalidResponse
    }

    func fetchAssignedTasks(baseURL: String, token: String) async throws -> [ZentaoTaskItem] {
        DebugLogger.log("Fetching assigned tasks from /my-work-task-assignedTo.json")
        let data = try await request(
            baseURL: baseURL,
            path: "/my-work-task-assignedTo.json",
            token: token
        )

        let tasks = try parseTaskListResponse(data)
        DebugLogger.log("Loaded assigned tasks: count=\(tasks.count)")
        return tasks
    }

    func fetchMyInvolvedTasks(baseURL: String, token: String) async throws -> [ZentaoTaskItem] {
        DebugLogger.log("Fetching involved tasks from /my-contribute-task-myInvolved")
        let data = try await request(
            baseURL: baseURL,
            path: "/my-contribute-task-myInvolved--id_desc.json",
            token: token
        )

        let tasks = try parseTaskListResponse(data)
        DebugLogger.log("Loaded involved tasks: count=\(tasks.count)")
        return tasks
    }

    func fetchTaskDetail(baseURL: String, token: String, taskID: Int) async throws -> ZentaoTaskDetailData {
        let data = try await request(
            baseURL: baseURL,
            path: "/task-view-\(taskID).json",
            token: token
        )

        guard let response = try? JSONDecoder().decode(ZentaoTaskDetailResponse.self, from: data),
              let innerData = response.data.data(using: .utf8),
              let detailData = try? JSONDecoder().decode(ZentaoTaskDetailData.self, from: innerData) else {
            throw ZentaoAPIError.invalidResponse
        }

        return detailData
    }

    func fetchTodayDynamic(baseURL: String, token: String, userID: Int) async throws -> ZentaoDynamicData {
        let data = try await request(
            baseURL: baseURL,
            path: "/company-dynamic-today--0--next-\(userID)-0-0-0-date_desc.json",
            token: token
        )

        guard let response = try? JSONDecoder().decode(ZentaoDynamicResponse.self, from: data),
              let innerData = response.data.data(using: .utf8),
              let dynamicData = try? JSONDecoder().decode(ZentaoDynamicData.self, from: innerData) else {
            throw ZentaoAPIError.invalidResponse
        }

        return dynamicData
    }

    private func request(
        baseURL: String,
        path: String,
        method: String = "GET",
        token: String? = nil,
        body: Data? = nil
    ) async throws -> Data {
        guard let url = buildURL(baseURL: baseURL, path: path) else {
            throw ZentaoAPIError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 20
        DebugLogger.log("HTTP \(method) \(url.absoluteString)")

        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        if let token {
            request.setValue(token, forHTTPHeaderField: "Token")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ZentaoAPIError.invalidResponse
        }

        DebugLogger.log("HTTP \(method) \(url.absoluteString) -> \(httpResponse.statusCode), bytes=\(data.count)")

        switch httpResponse.statusCode {
        case 200 ..< 300:
            return data
        case 401:
            throw ZentaoAPIError.unauthorized
        case 403:
            let message = String(data: data, encoding: .utf8)
            throw ZentaoAPIError.requestFailed(statusCode: httpResponse.statusCode, message: message)
        default:
            let message = String(data: data, encoding: .utf8)
            throw ZentaoAPIError.requestFailed(statusCode: httpResponse.statusCode, message: message)
        }
    }

    private func buildURL(baseURL: String, path: String) -> URL? {
        guard var components = URLComponents(string: baseURL) else {
            return nil
        }

        let pathParts = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let normalizedBasePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let normalizedRequestPath = String(pathParts[0]).trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        if normalizedBasePath.isEmpty {
            components.path = "/" + normalizedRequestPath
        } else if normalizedRequestPath.isEmpty {
            components.path = "/" + normalizedBasePath
        } else {
            components.path = "/" + normalizedBasePath + "/" + normalizedRequestPath
        }

        if pathParts.count > 1 {
            let query = String(pathParts[1])
            components.percentEncodedQuery = query.isEmpty ? nil : query
        } else {
            components.percentEncodedQuery = nil
        }

        return components.url
    }

    private func parseTaskListResponse(_ data: Data) throws -> [ZentaoTaskItem] {
        guard let response = try? JSONDecoder().decode(ZentaoTaskListResponse.self, from: data) else {
            DebugLogger.log("parseTaskListResponse: Failed to decode outer response")
            throw ZentaoAPIError.invalidResponse
        }

        let decodedData = response.data.unicodeDecodedString
        DebugLogger.log("parseTaskListResponse: status=\(response.status), data=\(decodedData.prefix(200)))")

        guard !response.data.isEmpty, response.data != "null" else {
            DebugLogger.log("parseTaskListResponse: data is empty or null")
            throw ZentaoAPIError.invalidResponse
        }

        guard let innerData = response.data.data(using: .utf8) else {
            DebugLogger.log("parseTaskListResponse: Failed to convert inner data to UTF-8")
            throw ZentaoAPIError.invalidResponse
        }

        guard let listData = try? JSONDecoder().decode(ZentaoTaskListData.self, from: innerData) else {
            DebugLogger.log("parseTaskListResponse: Failed to decode inner data: \(decodedData.unicodeDecodedString)")
            if response.data.contains("用户登录") || response.data.contains("login") {
                DebugLogger.log("parseTaskListResponse: Detected login page, token may be expired")
                throw ZentaoAPIError.unauthorized
            }
            throw ZentaoAPIError.invalidResponse
        }

        DebugLogger.log("parseTaskListResponse: parsed \(listData.tasks.count) tasks")
        return listData.tasks
    }
}

extension String {
    /// 将 Unicode 转义序列（如 \u7528\u6237）转换为中文
    var unicodeDecodedString: String {
        guard let data = self.data(using: .utf8) else { return self }
        guard let decoded = String(data: data, encoding: .utf8) else { return self }
        
        var result = decoded
        let pattern = #"\\u([0-9a-fA-F]{4})"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return decoded
        }
        
        var searchRange = NSRange(result.startIndex..., in: result)
        while let match = regex.firstMatch(in: result, options: [], range: searchRange) {
            guard let range = Range(match.range, in: result),
                  let hexRange = Range(match.range(at: 1), in: result) else { break }
            
            let hex = String(result[hexRange])
            if let codepoint = UInt32(hex, radix: 16),
               let scalar = UnicodeScalar(codepoint) {
                let replacement = String(Character(scalar))
                result.replaceSubrange(range, with: replacement)
                searchRange = NSRange(result.startIndex..., in: result)
            } else {
                break
            }
        }
        
        return result
    }
}