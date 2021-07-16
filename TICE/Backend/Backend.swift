//
//  Copyright © 2018 TICE Software UG (haftungsbeschränkt). All rights reserved.
//

import Foundation
import ConvAPI
import PromiseKit
import TICEAPIModels

class Backend {

    let api: API
    let baseURL: URL

    init(api: API, baseURL: URL) {
        self.api = api
        self.baseURL = baseURL
    }
    
    public func request<U>(method: APIMethod,
                           resource: String = "/",
                           headers: [String: String]? = nil,
                           params: [String: Any]? = nil,
                           decorator: ((inout URLRequest) -> Void)? = nil) -> Promise<U> where U: Codable {
        return firstly {
            api.request(method: method,
                        baseURL: baseURL,
                        resource: resource,
                        headers: headers,
                        params: params,
                        error: APIError.self,
                        decorator: decorator)
        }.map { (response: APIResponse<U>) -> U in
            switch response {
            case .success(let value):
                return value
            case .error(let error):
                throw error
            }
        }
    }
    
    public func request<T, U>(method: APIMethod,
                              resource: String = "/",
                              headers: [String: String]? = nil,
                              params: [String: Any]? = nil,
                              body: T? = nil,
                              decorator: ((inout URLRequest) -> Void)? = nil) -> Promise<U> where T: Encodable, U: Codable {
        return firstly {
            api.request(method: method,
                        baseURL: baseURL,
                        resource: resource,
                        headers: headers,
                        params: params,
                        body: body,
                        error: APIError.self,
                        decorator: decorator)
        }.map { (response: APIResponse<U>) -> U in
            switch response {
            case .success(let value):
                return value
            case .error(let error):
                throw error
            }
        }
    }
    
    public func request(method: APIMethod,
                        resource: String = "/",
                        headers: [String: String]? = nil,
                        params: [String: Any]? = nil,
                        decorator: ((inout URLRequest) -> Void)? = nil) -> Promise<Void> {
        let promise: Promise<EmptyAPIResponse> = api.request(method: method,
                                                             baseURL: baseURL,
                                                             resource: resource,
                                                             headers: headers,
                                                             params: params,
                                                             error: APIError.self,
                                                             decorator: decorator)
        return promise.map { (response: EmptyAPIResponse) in
            switch response {
            case .success:
                return
            case .error(let error):
                throw error
            }
        }
    }
    
    public func request<T>(method: APIMethod,
                           resource: String = "/",
                           headers: [String: String]? = nil,
                           params: [String: Any]? = nil,
                           body: T? = nil,
                           decorator: ((inout URLRequest) -> Void)? = nil) -> Promise<Void> where T: Encodable {
        let promise: Promise<EmptyAPIResponse> = api.request(method: method,
                           baseURL: baseURL,
                           resource: resource,
                           headers: headers,
                           params: params,
                           body: body,
                           error: APIError.self,
                           decorator: decorator)
        return promise.map { (response: EmptyAPIResponse) in
            switch response {
            case .success:
                return
            case .error(let error):
                throw error
            }
        }
    }
}
