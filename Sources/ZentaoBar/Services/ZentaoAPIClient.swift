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

    // MARK: - 1. 获取 Token

    func fetchToken(baseURL: String, account: String, password: String) async throws -> String {
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

        throw ZentaoAPIError.invalidResponse
    }

    // MARK: - 2. 获取当前用户信息

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

    // MARK: - 3. 获取当前分配的任务

    func fetchAssignedTasks(baseURL: String, token: String) async throws -> [ZentaoTaskItem] {
        let data = try await request(
            baseURL: baseURL,
            path: "/my-work-task-assignedTo.json",
            token: token
        )

        return try parseTaskListResponse(data)
    }

    // MARK: - 4. 获取我参与的任务（历史）

    func fetchMyInvolvedTasks(baseURL: String, token: String) async throws -> [ZentaoTaskItem] {
        let data = try await request(
            baseURL: baseURL,
            path: "/my-contribute-task-myInvolved--id_desc.json",
            token: token
        )

        return try parseTaskListResponse(data)
    }

    // MARK: - 5. 获取任务详情

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

    // MARK: - Private

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
        guard let response = try? JSONDecoder().decode(ZentaoTaskListResponse.self, from: data),
              let innerData = response.data.data(using: .utf8),
              let listData = try? JSONDecoder().decode(ZentaoTaskListData.self, from: innerData) else {
            throw ZentaoAPIError.invalidResponse
        }

        return listData.tasks
    }
}