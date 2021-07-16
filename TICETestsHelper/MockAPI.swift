//
//  Copyright © 2021 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import ConvAPI
import PromiseKit

@testable import TICE

enum MockAPIError: Error {
    case notImplemented
}

class MockAPI: API {

    var encoder = JSONEncoder.encoderWithFractionalSeconds
    var decoder = JSONDecoder.decoderWithFractionalSeconds

    var callback: (APIMethod, URL, String, [String: String]?, [String: Any]?, Data?) throws -> Any?

    init(callback: @escaping (APIMethod, URL, String, [String: String]?, [String: Any]?, Data?) throws -> Any) {
        self.callback = callback
    }

    func request<T, U, E>(method: APIMethod, baseURL: URL, resource: String, headers: [String: String]?, params: [String: Any]?, body: T?, error: E.Type, decorator: ((inout URLRequest) -> Void)?) -> Promise<U> where T: Encodable, U: Decodable, E: Decodable, E: Error {
        let serializedData: Data?
        if let body = body {
            serializedData = try? encoder.encode(body)
        } else {
            serializedData = nil
        }

        do {
            if let value = try callback(method, baseURL, resource, headers, params, serializedData) {
                // swiftlint:disable:next force_cast
                return Promise.value(value as! U)
            } else {
                return Promise(error: MockAPIError.notImplemented)
            }
        } catch {
            return Promise(error: error)
        }
    }
}
