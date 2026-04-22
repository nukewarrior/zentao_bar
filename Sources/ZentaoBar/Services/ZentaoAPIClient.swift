import Foundation

struct ZentaoAPIClient: @unchecked Sendable {
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
            return response.token
        }

        if let wrapped: ZentaoTokenResponse = try? decodeWrappedObject(
            ZentaoTokenResponse.self,
            from: data,
            rootKeys: ["data"]
        ) {
            return wrapped.token
        }

        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let token = object["token"] as? String {
            return token
        }

        DebugLogger.logResponsePreview(path: "/api.php/v1/tokens", data: data)
        throw ZentaoAPIError.invalidResponse
    }

    func fetchCurrentUser(baseURL: String, token: String) async throws -> ZentaoCurrentUser {
        let data = try await request(
            baseURL: baseURL,
            path: "/api.php/v1/user",
            token: token
        )

        if let user = try? JSONDecoder().decode(ZentaoCurrentUser.self, from: data) {
            return user
        }

        if let wrapped: ZentaoCurrentUser = try? decodeWrappedObject(
            ZentaoCurrentUser.self,
            from: data,
            rootKeys: ["data", "user", "profile"]
        ) {
            return wrapped
        }

        DebugLogger.logResponsePreview(path: "/api.php/v1/user", data: data)
        throw ZentaoAPIError.invalidResponse
    }

    func fetchAssignedTasks(baseURL: String, token: String) async throws -> [ZentaoTask] {
        let data = try await request(
            baseURL: baseURL,
            path: "/api.php/v1/tasks?assignedTo=me"
        ,
            token: token
        )

        return try decodeWrappedArray(
            ZentaoTask.self,
            from: data,
            rootKeys: ["data", "tasks", "items"]
        )
    }

    func fetchLegacyAssignedTasks(baseURL: String, token: String) async throws -> [ZentaoTask] {
        let candidatePaths = [
            "/my-work-task-assignedTo.json?zin=1",
            "/my-work-task-assignedTo.json?mode=json&zin=1",
            "/my-work-task-assignedTo.html?zin=1"
        ]

        var lastError: Error?

        for path in candidatePaths {
            do {
                let data = try await request(
                    baseURL: baseURL,
                    path: path,
                    token: token
                )

                DebugLogger.log("Legacy endpoint \(path) returned \(data.count) bytes")
                DebugLogger.logResponsePreview(path: path, data: data)

                let legacyJSONTasks = parseLegacyAssignedTasksJSON(data)
                if !legacyJSONTasks.isEmpty {
                    DebugLogger.log("Loaded tasks from legacy JSON endpoint \(path); count=\(legacyJSONTasks.count)")
                    return legacyJSONTasks
                }

                let htmlTasks = parseLegacyTaskListHTML(data)
                if !htmlTasks.isEmpty {
                    DebugLogger.log("Parsed tasks from legacy HTML endpoint \(path); count=\(htmlTasks.count)")
                    return htmlTasks
                }

                if let tasks = try? decodeWrappedArray(
                    ZentaoTask.self,
                    from: data,
                    rootKeys: ["data", "tasks", "items"]
                ), !tasks.isEmpty {
                    DebugLogger.log("Loaded tasks from generic legacy decoder \(path); count=\(tasks.count)")
                    return tasks
                }

                DebugLogger.log("Legacy endpoint \(path) returned no parsable tasks")
            } catch {
                lastError = error
                DebugLogger.log("Legacy endpoint \(path) failed: \(error.localizedDescription)")
            }
        }

        if let lastError {
            throw lastError
        }

        throw ZentaoAPIError.message("旧版“我的任务”入口未返回可解析的任务数据。")
    }

    func fetchProjects(baseURL: String, token: String) async throws -> [ZentaoProject] {
        let data = try await request(
            baseURL: baseURL,
            path: "/api.php/v1/projects?limit=1000",
            token: token
        )

        return try decodeWrappedArray(
            ZentaoProject.self,
            from: data,
            rootKeys: ["data", "projects", "items"]
        )
    }

    func fetchExecutions(baseURL: String, token: String) async throws -> [ZentaoExecution] {
        let data = try await request(
            baseURL: baseURL,
            path: "/api.php/v1/executions?limit=1000",
            token: token
        )

        return try decodeWrappedArray(
            ZentaoExecution.self,
            from: data,
            rootKeys: ["data", "executions", "items"]
        )
    }

    func fetchProjectExecutions(baseURL: String, token: String, projectID: Int) async throws -> [ZentaoExecution] {
        let data = try await request(
            baseURL: baseURL,
            path: "/api.php/v1/projects/\(projectID)/executions?limit=1000",
            token: token
        )

        return try decodeWrappedArray(
            ZentaoExecution.self,
            from: data,
            rootKeys: ["data", "executions", "items"]
        )
    }

    func fetchExecutionTasks(
        baseURL: String,
        token: String,
        executionID: Int,
        status: String? = nil
    ) async throws -> [ZentaoTask] {
        let path: String
        if let status, !status.isEmpty {
            path = "/api.php/v1/executions/\(executionID)/tasks?status=\(status)&limit=1000"
        } else {
            path = "/api.php/v1/executions/\(executionID)/tasks"
        }

        let data = try await request(
            baseURL: baseURL,
            path: path,
            token: token
        )

        return try decodeWrappedArray(
            ZentaoTask.self,
            from: data,
            rootKeys: ["data", "tasks", "items"]
        )
    }

    func fetchEstimates(baseURL: String, token: String, taskID: Int) async throws -> [ZentaoEstimate] {
        let data = try await request(
            baseURL: baseURL,
            path: "/api.php/v1/tasks/\(taskID)/estimate",
            token: token
        )

        return try decodeWrappedArray(
            ZentaoEstimate.self,
            from: data,
            rootKeys: ["data", "estimates", "items", "effort"]
        )
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
            DebugLogger.logResponsePreview(path: path, data: data)
            let message = String(data: data, encoding: .utf8)
            throw ZentaoAPIError.requestFailed(
                statusCode: httpResponse.statusCode,
                message: message
            )
        default:
            DebugLogger.logResponsePreview(path: path, data: data)
            let message = String(data: data, encoding: .utf8)
            throw ZentaoAPIError.requestFailed(
                statusCode: httpResponse.statusCode,
                message: message
            )
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

    private func decodeWrappedArray<T: Decodable>(
        _ type: T.Type,
        from data: Data,
        rootKeys: [String]
    ) throws -> [T] {
        let decoder = JSONDecoder()
        if let direct = try? decoder.decode([T].self, from: data) {
            return direct
        }

        if let directDictionary = try? decoder.decode([String: T].self, from: data) {
            return values(from: directDictionary)
        }

        if let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in rootKeys {
                guard let nested = object[key] else { continue }
                if let decoded = try? decodeArrayLikeValue(nested, as: T.self, decoder: decoder) {
                    return decoded
                }
            }
        }

        DebugLogger.logResponsePreview(path: rootKeys.joined(separator: ","), data: data)
        throw ZentaoAPIError.invalidResponse
    }

    private func decodeWrappedObject<T: Decodable>(
        _ type: T.Type,
        from data: Data,
        rootKeys: [String]
    ) throws -> T {
        let decoder = JSONDecoder()
        if let direct = try? decoder.decode(T.self, from: data) {
            return direct
        }

        if let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in rootKeys {
                guard let nested = object[key] else { continue }
                let nestedData = try JSONSerialization.data(withJSONObject: nested)
                if let decoded = try? decoder.decode(T.self, from: nestedData) {
                    return decoded
                }
            }
        }

        DebugLogger.logResponsePreview(path: rootKeys.joined(separator: ","), data: data)
        throw ZentaoAPIError.invalidResponse
    }

    private func decodeArrayLikeValue<T: Decodable>(
        _ value: Any,
        as type: T.Type,
        decoder: JSONDecoder
    ) throws -> [T] {
        let nestedData = try JSONSerialization.data(withJSONObject: value)

        if let decoded = try? decoder.decode([T].self, from: nestedData) {
            return decoded
        }

        if let decodedDictionary = try? decoder.decode([String: T].self, from: nestedData) {
            return values(from: decodedDictionary)
        }

        throw ZentaoAPIError.invalidResponse
    }

    private func values<T>(from dictionary: [String: T]) -> [T] {
        dictionary
            .sorted { left, right in
                if let leftInt = Int(left.key), let rightInt = Int(right.key) {
                    return leftInt < rightInt
                }

                return left.key < right.key
            }
            .map(\.value)
    }

    private func parseLegacyAssignedTasksJSON(_ data: Data) -> [ZentaoTask] {
        guard let root = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }

        var uniqueTasks: [Int: ZentaoTask] = [:]
        collectLegacyTasks(from: root, into: &uniqueTasks)

        return uniqueTasks.values.sorted { left, right in
            left.id < right.id
        }
    }

    private func collectLegacyTasks(from value: Any, into tasks: inout [Int: ZentaoTask]) {
        if let dictionary = value as? [String: Any] {
            if let task = legacyTask(from: dictionary) {
                tasks[task.id] = task
            }

            for nested in dictionary.values {
                collectLegacyTasks(from: nested, into: &tasks)
            }
            return
        }

        if let array = value as? [Any] {
            for nested in array {
                collectLegacyTasks(from: nested, into: &tasks)
            }
            return
        }

        if let string = value as? String,
           let nestedData = string.data(using: .utf8),
           let nestedRoot = try? JSONSerialization.jsonObject(with: nestedData) {
            collectLegacyTasks(from: nestedRoot, into: &tasks)
        }
    }

    private func legacyTask(from dictionary: [String: Any]) -> ZentaoTask? {
        let idKeys = ["id", "taskID", "taskId"]
        let nameKeys = ["name", "title", "taskName"]
        let assignedKeys = ["assignedTo", "assignedto"]
        let executionKeys = ["execution", "executionID", "executionId"]

        guard let id = firstIntValue(for: idKeys, in: dictionary),
              let name = firstStringValue(for: nameKeys, in: dictionary),
              !name.isEmpty else {
            return nil
        }

        return ZentaoTask(
            id: id,
            name: name,
            assignedTo: firstStringValue(for: assignedKeys, in: dictionary),
            execution: firstIntValue(for: executionKeys, in: dictionary)
        )
    }

    private func firstStringValue(for keys: [String], in dictionary: [String: Any]) -> String? {
        for key in keys {
            guard let value = dictionary[key] else { continue }
            if let string = value as? String {
                let normalized = normalizeLegacyHTMLText(string)
                if !normalized.isEmpty {
                    return normalized
                }
            } else if let number = value as? NSNumber {
                return number.stringValue
            }
        }
        return nil
    }

    private func firstIntValue(for keys: [String], in dictionary: [String: Any]) -> Int? {
        for key in keys {
            guard let value = dictionary[key] else { continue }
            if let intValue = value as? Int {
                return intValue
            }
            if let number = value as? NSNumber {
                return number.intValue
            }
            if let stringValue = value as? String, let intValue = Int(stringValue) {
                return intValue
            }
        }
        return nil
    }

    private func parseLegacyTaskListHTML(_ data: Data) -> [ZentaoTask] {
        guard let html = String(data: data, encoding: .utf8), !html.isEmpty else {
            return []
        }

        let pattern = #"href=["'][^"']*task(?:-view)?-(\d+)\.html[^"']*["'][^>]*>(.*?)</a>"#
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        let matches = regex.matches(in: html, options: [], range: range)
        var uniqueTasks: [Int: ZentaoTask] = [:]

        for match in matches {
            guard match.numberOfRanges >= 3,
                  let idRange = Range(match.range(at: 1), in: html),
                  let nameRange = Range(match.range(at: 2), in: html),
                  let id = Int(html[idRange]) else {
                continue
            }

            let rawName = String(html[nameRange])
            let name = normalizeLegacyHTMLText(rawName)
            guard !name.isEmpty else { continue }

            uniqueTasks[id] = ZentaoTask(
                id: id,
                name: name,
                assignedTo: nil,
                execution: nil
            )
        }

        return uniqueTasks.values.sorted { left, right in
            left.id < right.id
        }
    }

    private func normalizeLegacyHTMLText(_ rawValue: String) -> String {
        let withoutTags = rawValue.replacingOccurrences(
            of: "<[^>]+>",
            with: " ",
            options: .regularExpression
        )
        let decoded = withoutTags
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#039;", with: "'")

        return decoded
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
