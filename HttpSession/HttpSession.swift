//
//  HttpRequest.swift
//  FlyGo
//
//  Created by 范舟弛 on 2016/11/17.
//  Copyright © 2016年 舟弛 范. All rights reserved.
//

import UIKit
import ObjectMapper

/// HTTP 请求返回的错误
///
/// - requestFail: 请求过程中发生的错误
/// - serializerFail: 解析数据过程中发生的错误
enum HttpError : Error {
    case requestFail(errorMessage:String)
    case serializerFail
    case businessError(code:Int, description:String)
    case invalidData(Any)
    
    var description:String {
        switch self {
        case .serializerFail:
            return "返回数据错误。"
        case .requestFail(let errorMessage):
            return errorMessage
        case .businessError(_, let description):
            return description
        case .invalidData:
            return "无效的数据返回。"
        }
    }
    
    var localizedDescription:String {
        return description
    }
    
    static func description(ofHttpError error:Error) -> String {
        return (error as NSError)._requestErrorDescription()
    }
}

fileprivate extension NSError {
    func _requestErrorDescription() -> String {
        switch self.code {
        case NSURLErrorTimedOut:
            return "网络请求超时，请检查网络连接"
        case NSURLErrorNotConnectedToInternet:
            return "当前环境无网络，请检查网络连接"
        default:
            return "服务器连接错误，错误码\(self.code)，请检查网络连接或稍后重试"
        }
    }
}

/// HTTP 会话管理
class HttpSession {
    // HTTP 配置相关 可在AppDelegate上配置
    open static var urlConfig: URLConfig!
    
    /// AFNetworking 管理单列
    fileprivate static let urlManager:AFHTTPSessionManager = {
        guard let baseUrl = URL(string: HttpSession.urlConfig.baseURL) else {
            fatalError("Base Url Error")
        }
        
        let manager = AFHTTPSessionManager(baseURL: baseUrl,
                                           sessionConfiguration: URLSessionConfiguration.default)
        
        manager.responseSerializer = AFHTTPResponseSerializer()
        
        manager.completionQueue = DispatchQueue(label: "com.latte.httpsession")
        
        /// https 
        let securityPolicy = AFSecurityPolicy.default()
        
        securityPolicy.allowInvalidCertificates = true
        securityPolicy.validatesDomainName = false
        
        manager.securityPolicy = securityPolicy
        
        /// response
        
        manager.responseSerializer.acceptableContentTypes = ["text/plain", "text/json", "text/html","text/xml", "application/json"]
        
        return manager
    }()
    
    fileprivate static let jsonResponseSerializer:AFJSONResponseSerializer = {
        () -> AFJSONResponseSerializer in
        let responseSerializer = AFJSONResponseSerializer()
        
        responseSerializer.acceptableContentTypes = ["text/plain", "text/json", "text/html","text/xml", "application/json"]
        
        return responseSerializer
    }()
    
    weak var dataTask:URLSessionTask? = nil
    
    /// 回调管理
    fileprivate var response:HttpResponse? = nil
    
    /// 403
    static var tokenInValidHandler:(() -> Void)? = nil
    
    static var tokenInValidCondition:(() -> Bool)? = nil
    
    /// 头域
    typealias GetHeaderHandler = () -> [String:String?]
    
    static var getHeaderHandler:GetHeaderHandler? = nil
    
    fileprivate static func setupHeader(isJson:Bool = false) {
        if isJson {
            urlManager.requestSerializer = AFJSONRequestSerializer()
        } else {
            urlManager.requestSerializer = AFHTTPRequestSerializer()
        }
        
        let requestSerializer = urlManager.requestSerializer
        
        requestSerializer.setValue(HttpSession.urlConfig.version,
                                   forHTTPHeaderField: HttpSession.urlConfig.versionKeyInHeader)
        
        if let dict = getHeaderHandler?() {
            for (key, value) in dict {
                if let stringValue = value {
                    requestSerializer.setValue(stringValue, forHTTPHeaderField: key)
                }
            }
        }
    }
    
    fileprivate var getTask:(() -> URLSessionDataTask?)!
    
    fileprivate func setupTask() {
        self.dataTask = getTask()
    }
    
    static var validingSessionQueue:[HttpSession] = []
    
    static let requestQueue:DispatchQueue = DispatchQueue(label: "com.latte.httpsession")
    
    static var validingToken:Bool = false
    
    static let tokenLock = NSRecursiveLock()
}

// MARK: - 请求相关
extension HttpSession {
    static func get(urlString:String,
                    params:Any? = nil) -> HttpSession {
        
        let session = HttpSession()
        
        requestQueue.async {
            setupHeader()
            
            session.getTask = {
                [weak session] in
                
                guard let `session` = session else {
                    return nil
                }
                
                return HttpSession
                    .urlManager
                    .get(urlString,
                         parameters: params,
                         progress: nil,
                         success: {
                            (task, data) in
                            
                            session.response?.success(task, data)
                    },
                         failure: {
                            (task, error) in
                            
                            session.response?.failure(task, error)
                    })
            }
            
            session.setupTask()
        }
        
        return session
    }
    
    static func post(urlString:String,
                     isJson:Bool = false,
                     params:Any?) -> HttpSession {
        let session = HttpSession()
        
        requestQueue.async {
            setupHeader(isJson:isJson)
            
            session.getTask = {
                [weak session] in
                
                guard let `session` = session else {
                    return nil
                }
                
                return HttpSession
                    .urlManager
                    .post(urlString,
                          parameters: params,
                          progress: nil,
                          success: {
                            (task, data) in
                            
                            session.response?.success(task, data)
                    },
                          failure: {
                            (task, error) in
                            
                            session.response?.failure(task, error)
                    })
            }
            
            session.setupTask()
        }
        
        return session
    }
}


// MARK: - 回调相关
extension HttpSession {
    
    @discardableResult
    func responseNoModel(_ handler:@escaping () -> Void,
                         error:((HttpError) -> Void)? = nil) -> HttpResponse {
        
        self.response = HttpNoModelResponse(handler)
        
        self.response!.error(error)
        
        return self.response!
    }
    
    @discardableResult
    func responseModel<T:Model>(_ handler:@escaping (T) -> Void,
                                  error:((HttpError) -> Void)? = nil) -> HttpResponse {
        
        self.response = HttpModelResponse(handler)
        
        self.response!.error(error)
        
        return self.response!
    }
    
    @discardableResult
    func responseModelList<T:Model>(_ handler:@escaping ([T]) -> Void,
                                      error:((HttpError) -> Void)? = nil) -> HttpResponse {
        
        self.response = HttpModelArrayResponse(handler)
        
        self.response!.error(error)
        
        return self.response!
    }
    
    @discardableResult
    func responseModelDict<T:Model>(_ handler:@escaping ([String:[T]]) -> Void,
                           error:((HttpError) -> Void)? = nil) -> HttpResponse {
        
        self.response = HttpModelDictionaryResponse(handler)
        
        self.response!.error(error)
        
        return self.response!
    }
    
    @discardableResult
    func responseJSON(_ handler:@escaping (Any) -> Void,
                        error:((HttpError) -> Void)? = nil) -> HttpResponse {
        
        self.response = HttpJSONResponse(handler)
        
        self.response!.error(error)
        
        return self.response!
    }
    
    @discardableResult
    func responseString(_ handler:@escaping (String) -> Void,
                          error:((HttpError) -> Void)? = nil) -> HttpResponse {
        
        self.response = HttpStringResponse(handler)
        
        self.response!.error(error)
        
        return self.response!
    }
    
}

/// 定义标准回调协议
protocol HttpResponse {
    func error(_ handler:((HttpError) -> Void)?)
    
    var success: (URLSessionDataTask, Any?) -> Void {get}
    
    var failure: (URLSessionDataTask?, Error) -> Void {get}
}


/// 标准JSON请求回调
fileprivate class HttpStringResponse : HttpResponse  {
    
    init(_ handler:@escaping ((String) -> Void)) {
        completeHandler = handler
    }
    
    let completeHandler:((String) -> Void)
    
    var errorHander:((HttpError) -> Void)? = nil
    
    func error(_ handler:((HttpError) -> Void)?) {
        self.errorHander = handler
    }
    
    var success: (URLSessionDataTask, Any?) -> Void {
        get {
            return {
                (dataTask, data) in
                
                guard let responseData = data as? Data else {
                    self.errorHander?(.serializerFail)
                    
                    return
                }
                
                guard let responseString = String(data: responseData,
                                                  encoding: String.Encoding.utf8) else {
                                                    self.errorHander?(.serializerFail)
                                                    
                                                    return
                                                    
                }
                
                self.completeHandler(responseString)
            }
        }
    }
    
    var failure: (URLSessionDataTask?, Error) -> Void {
        get {
            return {
                (_, error) in
                self.errorHander?(.requestFail(errorMessage:(error as NSError)._requestErrorDescription()))
            }
        }
    }
}

/// 标准JSON请求回调
fileprivate class HttpJSONResponse : HttpResponse  {
    
    init(_ handler:@escaping ((Any) -> Void)) {
        completeHandler = handler
    }
    
    let completeHandler:((Any) -> Void)
    
    var errorHander:((HttpError) -> Void)? = nil
    
    func error(_ handler:((HttpError) -> Void)?) {
        self.errorHander = handler
    }
    
    var success: (URLSessionDataTask, Any?) -> Void {
        get {
            return {
                (dataTask, data) in
                
                guard var responseData = data as? Data else {
                    self.errorHander?(.serializerFail)
                    
                    return
                }
                
                if let encoding = dataTask.response?.textEncodingName, encoding == "gbk" {
                    let enc = CFStringConvertEncodingToNSStringEncoding(UInt32(CFStringEncodings.GB_18030_2000.rawValue))
                    
                    let encString = NSString(data: responseData,
                                             encoding: enc)
                    
                    if let utf8Data = encString?.data(using: String.Encoding.utf8.rawValue) {
                        responseData = utf8Data
                    }
                }
                
                let serializer = HttpSession.jsonResponseSerializer
                
                let error:NSErrorPointer = nil
                
                guard let json = serializer.responseObject(for: dataTask.response,
                                                           data: responseData,
                                                           error: error) else {
                                                            
                                                            self.errorHander?(.serializerFail)
                                                            
                                                            return
                }
                
                
                self.completeHandler(json)
            }
        }
    }
    
    var failure: (URLSessionDataTask?, Error) -> Void {
        get {
            return {
                (_, error) in
                self.errorHander?(.requestFail(errorMessage:(error as NSError)._requestErrorDescription()))
            }
        }
    }
}

/// 标准回调模型结构
fileprivate struct HttpModelResponseStruct: Mappable {
    var code:Int!
    
    var message:String!
    
    var result:Any!
    
    init?(map: Map) {
        
        code    <- (map[HttpSession.urlConfig.responseDataKey.code], APITransform.IntTransform())
        
        guard let code = self.code else {
            return nil
        }
        
        message <- map[HttpSession.urlConfig.responseDataKey.message]
        
        if code != 0 && message == nil {
            return nil
        }
        
        result  <- map[HttpSession.urlConfig.responseDataKey.data]
    }
    
    mutating func mapping(map: Map) {
        code    <- (map[HttpSession.urlConfig.responseDataKey.code], APITransform.IntTransform())
        
        message <- map[HttpSession.urlConfig.responseDataKey.message]
        
        result  <- map[HttpSession.urlConfig.responseDataKey.data]
    }
    
    var isSuccess:Bool {
        return code == 0
    }
    
    func getModel<M:Model>() throws -> M {
        if code != 0 {
            throw HttpError.businessError(code: code ?? -1,
                                          description: message)
        }
        
        var model:M? = nil
        
        if let array = result as? [[String:Any]], array.count > 0 {
            model = M(JSON: array[0])
        } else if let json = result as? [String:Any] {
            model = M(JSON: json)
        } else if result == nil {
            model = M(JSON: [String:String]())
        }
        
        guard let _model = model else {
            throw HttpError.invalidData(result)
        }
        
        return _model
    }
    
    func getModelList<M:Model>() throws -> [M] {
        if code != 0 {
            throw HttpError.businessError(code: code ?? -1,
                                          description: message)
        }
        
        var model:[M] = []
        
        if let array = result as? [[String:Any]], array.count > 0 {
            model = array.map({ M(JSON: $0) }).filter({ $0 != nil }).map({ $0! })
        } else if let json = result as? [String:Any] {
            if json.keys.count > 1, let _model = M(JSON: json) {
                model.append(_model)
            }
        } else if result == nil {
            model = []
        }
        
        return model
    }
    
    func getModelDictionary<M:Model>() throws -> [String:[M]] {
        if code != 0 {
            throw HttpError.businessError(code: code ?? -1,
                                          description: message)
        }
        
        var model:[String:[M]] = [:]
        
        if let json = result as? [String:Any] {
            
            let keys = json.keys
            
            for key in keys {
                if let array = json[key] as? [[String:Any]] {
                    model[key] = array.map({ M(JSON: $0) }).filter({ $0 != nil }).map({ $0! })
                } else if let dict = json[key] as? [String:Any], let one = M(JSON: dict) {
                    model[key] = [one]
                } else {
                    model[key] = []
                }
            }
        }
        
        return model
    }
}

extension HttpSession {
    static func model<M:Model>(from json:Any) throws -> M {
        
        guard let dict = json as? [String:Any] else {
            throw HttpError.serializerFail
        }
        
        guard let responseModel = HttpModelResponseStruct(JSON: dict) else {
            throw HttpError.serializerFail
        }
        
        do {
            let model:M = try responseModel.getModel()
            
            return model
        } catch HttpError.businessError(let code, let description) {
            throw HttpError.businessError(code: code,
                                          description: description)
        } catch HttpError.requestFail(let errorMessage) {
            throw HttpError.requestFail(errorMessage: errorMessage)
        } catch {
            throw HttpError.serializerFail
        }
    }
}

/// 无模型回调
fileprivate class HttpNoModelResponse : HttpResponse {
    init(_ handler:@escaping (() -> Void)) {
        completeHandler = handler
    }
    
    let completeHandler:(() -> Void)
    
    var errorHander:((HttpError) -> Void)? = nil
    
    func error(_ handler:((HttpError) -> Void)?) {
        self.errorHander = handler
    }
    
    var success: (URLSessionDataTask, Any?) -> Void {
        get {
            return {
                (dataTask, data) in
                
                guard var responseData = data as? Data else {
                    self.errorHander?(.serializerFail)
                    return
                }
                
                if let encoding = dataTask.response?.textEncodingName, encoding == "gbk" {
                    let enc = CFStringConvertEncodingToNSStringEncoding(UInt32(CFStringEncodings.GB_18030_2000.rawValue))
                    
                    let encString = NSString(data: responseData,
                                             encoding: enc)
                    
                    if let utf8Data = encString?.data(using: String.Encoding.utf8.rawValue) {
                        responseData = utf8Data
                    }
                }
                
                let serializer = HttpSession.jsonResponseSerializer
                
                let error:NSErrorPointer = nil
                
                guard let json = serializer.responseObject(for: dataTask.response,
                                                           data: responseData,
                                                           error: error) as? [String: Any]
                    else {
                        self.errorHander?(.serializerFail)
                        return
                }
                
                guard let resp = HttpModelResponseStruct(JSON:json) else {
                    self.errorHander?(.serializerFail)
                    return
                }
                
                if resp.isSuccess {
                    self.completeHandler()
                } else {
                    self.errorHander?(.businessError(code:resp.code ?? -1,
                                                     description:resp.message))
                }
            }
        }
    }
    
    var failure: (URLSessionDataTask?, Error) -> Void {
        get {
            return {
                (_, error) in
                self.errorHander?(.requestFail(errorMessage:(error as NSError)._requestErrorDescription()))
            }
        }
    }
}

/// 标准Model请求回调
fileprivate class HttpModelResponse<T:Model> : HttpResponse  {
    
    init(_ handler:@escaping ((T) -> Void)) {
        completeHandler = handler
    }
    
    let completeHandler:((T) -> Void)
    
    var errorHander:((HttpError) -> Void)? = nil
    
    func error(_ handler:((HttpError) -> Void)?) {
        self.errorHander = handler
    }
    
    var success: (URLSessionDataTask, Any?) -> Void {
        get {
            return {
                (dataTask, data) in
                
                guard var responseData = data as? Data else {
                    self.errorHander?(.serializerFail)
                    return
                }
                
                if let encoding = dataTask.response?.textEncodingName, encoding == "gbk" {
                    let enc = CFStringConvertEncodingToNSStringEncoding(UInt32(CFStringEncodings.GB_18030_2000.rawValue))
                    
                    let encString = NSString(data: responseData,
                                             encoding: enc)
                    
                    if let utf8Data = encString?.data(using: String.Encoding.utf8.rawValue) {
                        responseData = utf8Data
                    }
                }
                
                let serializer = HttpSession.jsonResponseSerializer
                
                let error:NSErrorPointer = nil
                
                guard let json = serializer.responseObject(for: dataTask.response,
                                                           data: responseData,
                                                           error: error) as? [String: Any]
                    else {
                        self.errorHander?(.serializerFail)
                        return
                }
                
                guard let resp = HttpModelResponseStruct(JSON:json) else {
                    self.errorHander?(.serializerFail)
                    return
                }
                
                do {
                    let model:T = try resp.getModel()
                    
                    self.completeHandler(model)
                } catch HttpError.businessError(let code, let description) {
                    self.errorHander?(.businessError(code:code,
                                                      description:description))
                } catch HttpError.invalidData(let json) {
                    self.errorHander?(.invalidData(json))
                } catch  {
                    self.errorHander?(.serializerFail)
                }
            }
        }
    }
    
    var failure: (URLSessionDataTask?, Error) -> Void {
        get {
            return {
                (_, error) in
                self.errorHander?(.requestFail(errorMessage:(error as NSError)._requestErrorDescription()))
            }
        }
    }
}


/// 标准Model数组请求回调
fileprivate class HttpModelArrayResponse<T:Model> : HttpResponse  {
    
    init(_ handler:@escaping (([T]) -> Void)) {
        completeHandler = handler
    }
    
    let completeHandler:(([T]) -> Void)
    
    var errorHander:((HttpError) -> Void)? = nil
    
    func error(_ handler:((HttpError) -> Void)?) {
        self.errorHander = handler
    }
    
    var success: (URLSessionDataTask, Any?) -> Void {
        get {
            return {
                (dataTask, data) in
                
                guard var responseData = data as? Data else {
                    self.errorHander?(.serializerFail)
                    
                    return
                }
                
                if let encoding = dataTask.response?.textEncodingName, encoding == "gbk" {
                    let enc = CFStringConvertEncodingToNSStringEncoding(UInt32(CFStringEncodings.GB_18030_2000.rawValue))
                    
                    let encString = NSString(data: responseData,
                                             encoding: enc)
                    
                    if let utf8Data = encString?.data(using: String.Encoding.utf8.rawValue) {
                        responseData = utf8Data
                    }
                }
                
                let serializer = HttpSession.jsonResponseSerializer
                
                let error:NSErrorPointer = nil
                
                guard let json = serializer.responseObject(for: dataTask.response,
                                                     data: responseData,
                                                     error: error) as? [String: Any]
                    else {
                        self.errorHander?(.serializerFail)
                        return
                }
                
                guard let resp = HttpModelResponseStruct(JSON:json) else {
                    self.errorHander?(.serializerFail)
                    return
                }
                
                do {
                    let models:[T] = try resp.getModelList()
                    
                    self.completeHandler(models)
                } catch HttpError.businessError(let code, let description) {
                    self.errorHander?(.businessError(code:code,
                                                     description:description))
                } catch {
                    self.errorHander?(.serializerFail)
                }
            }
        }
    }
    
    var failure: (URLSessionDataTask?, Error) -> Void {
        get {
            return {
                (_, error) in
                self.errorHander?(.requestFail(errorMessage:(error as NSError)._requestErrorDescription()))
            }
        }
    }
}


/// 标准Model字典请求回调
fileprivate class HttpModelDictionaryResponse<T:Model> : HttpResponse  {
    
    init(_ handler:@escaping (([String:[T]]) -> Void)) {
        completeHandler = handler
    }
    
    let completeHandler:(([String:[T]]) -> Void)
    
    var errorHander:((HttpError) -> Void)? = nil
    
    func error(_ handler:((HttpError) -> Void)?) {
        self.errorHander = handler
    }
    
    var success: (URLSessionDataTask, Any?) -> Void {
        get {
            return {
                (dataTask, data) in
                
                guard var responseData = data as? Data else {
                    self.errorHander?(.serializerFail)
                    
                    return
                }
                
                if let encoding = dataTask.response?.textEncodingName, encoding == "gbk" {
                    let enc = CFStringConvertEncodingToNSStringEncoding(UInt32(CFStringEncodings.GB_18030_2000.rawValue))
                    
                    let encString = NSString(data: responseData,
                                             encoding: enc)
                    
                    if let utf8Data = encString?.data(using: String.Encoding.utf8.rawValue) {
                        responseData = utf8Data
                    }
                }
                
                let serializer = HttpSession.jsonResponseSerializer
                
                let error:NSErrorPointer = nil
                
                guard let json = serializer.responseObject(for: dataTask.response,
                                                           data: responseData,
                                                           error: error) as? [String: Any]
                    else {
                        self.errorHander?(.serializerFail)
                        return
                }
                
                guard let resp = HttpModelResponseStruct(JSON:json) else {
                    self.errorHander?(.serializerFail)
                    return
                }
                
                do {
                    let models:[String:[T]] = try resp.getModelDictionary()
                    
                    self.completeHandler(models)
                } catch HttpError.businessError(let code, let description) {
                    self.errorHander?(.businessError(code:code,
                                                     description:description))
                } catch {
                    self.errorHander?(.serializerFail)
                }
            }
        }
    }
    
    var failure: (URLSessionDataTask?, Error) -> Void {
        get {
            return {
                (_, error) in
                self.errorHander?(.requestFail(errorMessage:(error as NSError)._requestErrorDescription()))
            }
        }
    }
}




