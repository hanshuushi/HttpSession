//
//  API.swift
//  FlyGo
//
//  Created by Latte on 2016/11/10.
//  Copyright © 2016年 舟弛 范. All rights reserved.
//

import Foundation
import ObjectMapper

protocol ModelType { }

protocol Model: Mappable, ModelType {
    
}

protocol ModelListTyper: ModelType {
    associatedtype M : Model
    
    var list:[M] {get}
}


struct ModelList<M:Model>: ModelListTyper {
    var list:[M] = []
    
    init() {
        
    }
    
    init(_ list:[M]) {
        self.list = list
    }
}

struct ModelDictionary<M:Model>: ModelType  {
    var dict:[String:[M]] = [:]
    
    init() {
        
    }
    
    init(_ dict:[String:[M]]) {
        self.dict = dict
    }
}

enum PostItem {
    case success
    
    case requesting
    
    case failed(error: String)
}

protocol APIItemTyper {
    associatedtype M: ModelType
    
    var model:M? { get }
    
    var isSuccess:Bool { get }
    
    var isFinish:Bool { get }
}

fileprivate extension String {
    func to64Int() -> Int64? {
        if let num = NumberFormatter().number(from: self) {
            return num.int64Value
        } else {
            return nil
        }
    }
}

enum APIItem<T: ModelType>: APIItemTyper {
    case success(model: T)
    
    case validating
    
    case failed(error: String)
    
    func map<R:ModelType>(_ transform: (T) -> R) -> APIItem<R> {
        switch self {
        case .validating:
            return .validating
        case .failed(let error):
            return .failed(error: error)
        case .success(let model):
            let result = transform(model)
            
            return APIItem<R>.success(model: result)
        }
    }
    
    var model:T? {
        switch self {
        case .success(let model):
            return model
        default:
            return nil
        }
    }
    
    var isSuccess:Bool {
        switch self {
        case .success(_):
            return true
        default:
            return false
        }
    }
    
    var isFinish:Bool {
        switch self {
        case .success(_):
            return true
        case .failed(_):
            return true
        default:
            return false
        }
    }
    
    var postItem:PostItem {
        switch self {
        case .success(model: _):
            return .success
        case .failed(let error):
            return .failed(error: error)
        case .validating:
            return .requesting
        }
    }
}

extension APIItem where T : ModelListTyper {
    func map<R>(transform:((T.M) -> R)) -> [R] {
        switch self {
        case .success(let model):
            return model.list.map{transform($0)}
        default:
            return []
        }
    }
}


struct APITransform {
    struct URLTransform : TransformType {
        func transformFromJSON(_ value: Any?) -> URL? {
            
            if let string = value as? String {
                return URL(string: string)
            } else if let array = value as? [String], array.count > 0 {
                return URL(string: array[0])
            }
            
            return nil
        }
        
        func transformToJSON(_ value: URL?) -> String? {
            return value.map({ $0.absoluteString })
        }
    }
    
    struct PicTransform : TransformType {
        
        static func url(from string:String) -> URL? {
            if string.hasPrefix("http://") || string.hasPrefix("https://") {
                return URL(string: string)
            }
            
            return URL(string: HttpSession.urlConfig.basePicURL + string)
        }
        
        func transformFromJSON(_ value: Any?) -> URL? {
            if let string = value as? String {
                return PicTransform.url(from: string)
            } else if let array = value as? [String], array.count > 0 {
                return PicTransform.url(from: array[0])
            }
            
            return nil
        }
        
        func transformToJSON(_ value: URL?) -> String? {
            return value.map({ $0.absoluteString.replacingOccurrences(of: HttpSession.urlConfig.basePicURL,
                                                                      with: "") })
        }
    }
    
    struct Base64Transform : TransformType {
        func transformFromJSON(_ value: Any?) -> UIImage? {
            if let string = value as? String {
                return Data(base64Encoded: string,
                            options: .ignoreUnknownCharacters)
                    .flatMap({
                        UIImage(data: $0)
                    })
            } else if let array = value as? [String], array.count > 0 {
                return Data(base64Encoded: array[0],
                            options: .ignoreUnknownCharacters)
                    .flatMap({
                        UIImage(data: $0)
                    })
            }
            
            return nil
        }
        
        func transformToJSON(_ value: UIImage?) -> String? {
            return value.flatMap({ UIImagePNGRepresentation($0)?.base64EncodedString() })
        }
    }
    
    struct PicsTransform : TransformType {
        func transformFromJSON(_ value: Any?) -> [URL]? {
            if let string = value as? String {
                return [PicTransform.url(from: string)]
                    .filter({ $0 != nil })
                    .map({ $0! })
            } else if let array = value as? [String], array.count > 0 {
                return array.map({ PicTransform.url(from: $0) }).filter({ $0 != nil })
                    .map({ $0! })
            }
            
            return []
        }
        
        func transformToJSON(_ value: [URL]?) -> String? {
            return ""
        }
    }
    
    struct StringTransform: TransformType {
        func transformFromJSON(_ value: Any?) -> String? {
            return value.map({ String(describing: $0) })
        }
        
        func transformToJSON(_ value: String?) -> String? {
            return value
        }
    }
    
    struct IntTransform: TransformType {
        func transformFromJSON(_ value: Any?) -> Int? {
            return value
                .flatMap{String(describing: $0)}
                .flatMap{Int($0)}
        }
        
        func transformToJSON(_ value: Int?) -> String? {
            return value.flatMap({ "\($0)" })
        }
    }
    
    struct FloatTransform: TransformType {
        func transformFromJSON(_ value: Any?) -> Float? {
            return value
                .flatMap{String(describing: $0)}
                .flatMap{$0.toFloat()}
        }
        
        func transformToJSON(_ value: Float?) -> String? {
            return value.flatMap({ "\($0)" })
        }
    }
    
    struct DoubleTransform: TransformType {
        func transformFromJSON(_ value: Any?) -> Double? {
            return value
                .flatMap{String(describing: $0)}
                .flatMap{$0.toDouble()}
        }
        
        func transformToJSON(_ value: Double?) -> String? {
            return value.flatMap({ "\($0)" })
        }
    }
    
    struct BoolTransform: TransformType {
        func transformFromJSON(_ value: Any?) -> Bool? {
            return value
                .flatMap{ (v) -> Bool in
                    if let bv = v as? Bool {
                        return bv
                    } else if let iv = v as? Int {
                        return iv > 0
                    } else if let sv = v as? String {
                        return sv != "0"
                    } else {
                        return true
                    }
            }
        }
        
        func transformToJSON(_ value: Bool?) -> Int? {
            return value.map{$0 ? 1 : 0}
        }
    }
    
    struct DateTransform: TransformType {
        func transformFromJSON(_ value: Any?) -> Date? {
            return value.flatMap({ (val) -> Date? in
                
                let stringValue = String(describing: val)
                
                if stringValue.isNumber() {
                    guard var timestamp = stringValue.toDouble(),
                        timestamp >= 1000000000 else  {
                        return nil
                    }
                    
                    timestamp = timestamp / 1000
                    
                    return Date(timeIntervalSince1970: TimeInterval(timestamp))
                }
                
                if let date = Date(fromString: stringValue, format: "YYYY-MM-dd HH:mm:ss") {
                    return date
                }
                
                if let date = Date(fromString: stringValue, format: "YYYY-MM-dd HH:mm") {
                    return date
                }
                
                if let date = Date(fromString: stringValue, format: "YYYYMMdd HH:mm:ss") {
                    return date
                }
                
                return nil
            })
        }
        
        func transformToJSON(_ value: Date?) -> Double? {
            
            return value.flatMap({ (date) -> Double in
                return Double(date.timeIntervalSince1970 * 1000)
            })
        }
    }
    
}

//extension HttpSession: Disposable {
//    func dispose() {
//        self.dataTask?.cancel()
//        self.dataTask = nil
//    }
//}

//extension HttpSession {
//    static func get<M:Model>(urlString:String,
//                    params:Any? = nil) -> Observable<APIItem<M>> {
//        return Observable.create({ (observer) -> Disposable in
//            observer.onNext(.validating)
//
//            let session = HttpSession.get(urlString: urlString,
//                                          params: params)
//
//            session.responseModel({ (model:M) in
//                observer.onNext(.success(model:model))
//                observer.onCompleted()
//            }).error({ (error) in
//                observer.onNext(.failed(error:error.description))
//                observer.onCompleted()
//            })
//
//            return session
//        }).observeOn(MainScheduler.instance)
//    }
//
//#if DEBUG
//    static func getTest<M:Model>(urlString:String,
//                    params:Any? = nil) -> Observable<APIItem<M>> {
//        return Observable.create({ (observer) -> Disposable in
//            observer.onNext(.validating)
//
//            let session = HttpSession.get(urlString: urlString,
//                                          params: params)
//
//            session.responseModel({ (model:M) in
//
//                let index = arc4random() % 3
//
//                if index == 2 {
//                    ez.runThisAfterDelay(seconds: 3.0,
//                                         after: {
//                                            observer.onNext(.failed(error:"测试错误"))
//                                            observer.onCompleted()
//                    })
//
//                    return
//                }
//
//                ez.runThisAfterDelay(seconds: 3.0,
//                                     after: {
//                                        observer.onNext(.success(model:model))
//                                        observer.onCompleted()
//                })
//
//            }).error({ (error) in
//                observer.onNext(.failed(error:error.description))
//                observer.onCompleted()
//            })
//
//            return session
//        }).observeOn(MainScheduler.instance)
//    }
//
//    static func getTest<M:Model>(urlString:String,
//                        params:Any? = nil) -> Observable<APIItem<ModelList<M>>> {
//        return Observable.create({ (observer) -> Disposable in
//            observer.onNext(.validating)
//
//            let session = HttpSession.get(urlString: urlString,
//                                          params: params)
//
//            session.responseModelList({ (models:[M]) in
//
//                let index = arc4random() % 3
//
//                if index == 2 {
//                    ez.runThisAfterDelay(seconds: 3.0,
//                                         after: {
//                                            observer.onNext(.failed(error:"测试错误"))
//                                            observer.onCompleted()
//                    })
//
//                    return
//                }
//
//                ez.runThisAfterDelay(seconds: 3.0,
//                                     after: {
//                                        observer.onNext(.success(model:ModelList(models)))
//                                        observer.onCompleted()
//                })
//
//            }).error({ (error) in
//                observer.onNext(.failed(error:error.description))
//                observer.onCompleted()
//            })
//
//            return session
//        }).observeOn(MainScheduler.instance)
//    }
//#endif
//
//    static func get<M:Model>(urlString:String,
//                    params:Any? = nil) -> Observable<APIItem<ModelList<M>>> {
//        return Observable.create({ (observer) -> Disposable in
//            observer.onNext(.validating)
//
//            let session = HttpSession.get(urlString: urlString,
//                                          params: params)
//
//            session.responseModelList({ (models:[M]) in
//                observer.onNext(.success(model:ModelList(models)))
//            }).error({ (error) in
//                observer.onNext(.failed(error:error.description))
//            })
//
//            return session
//        }).observeOn(MainScheduler.instance)
//    }
//
//    static func post(urlString:String,
//                     isJson:Bool = false,
//                     params:Any) -> Observable<PostItem> {
//
//        return Observable.create({ (observer) -> Disposable in
//            observer.onNext(PostItem.requesting)
//
//            let session:HttpSession = HttpSession.post(urlString: urlString,
//                                                       isJson: isJson,
//                                                       params: params)
//
//            session.responseNoModel({
//                observer.onNext(PostItem.success)
//                observer.onCompleted()
//            }).error({ (error) in
//                observer.onNext(PostItem.failed(error: error.description))
//                observer.onCompleted()
//            })
//
//            return session
//        }).observeOn(MainScheduler.instance)
//    }
//
//    static func post<M:Model>(urlString:String,
//                     isJson:Bool = false,
//                     params:Any? = nil) -> Observable<APIItem<M>> {
//        return Observable.create({ (observer) -> Disposable in
//            observer.onNext(.validating)
//
//            let session = HttpSession.post(urlString: urlString,
//                                           isJson: isJson,
//                                           params: params)
//
//            session.responseModel({ (model:M) in
//                observer.onNext(.success(model:model))
//                observer.onCompleted()
//            }).error({ (error) in
//                observer.onNext(.failed(error:error.description))
//                observer.onCompleted()
//            })
//
//            return session
//        }).observeOn(MainScheduler.instance)
//    }
//
//    static func post<M:Model>(urlString:String,
//                     isJson:Bool = false,
//                     params:Any? = nil) -> Observable<APIItem<ModelList<M>>> {
//        return Observable.create({ (observer) -> Disposable in
//            observer.onNext(.validating)
//
//            let session = HttpSession.post(urlString: urlString,
//                                           isJson: isJson,
//                                           params: params)
//
//            session.responseModelList({ (models:[M]) in
//                observer.onNext(.success(model:ModelList(models)))
//                observer.onCompleted()
//            }).error({ (error) in
//                observer.onNext(.failed(error:error.description))
//                observer.onCompleted()
//            })
//
//            return session
//        }).observeOn(MainScheduler.instance)
//    }
//
//    static func post<M:Model>(urlString:String,
//                     isJson:Bool = false,
//                     params:Any? = nil) -> Observable<APIItem<ModelDictionary<M>>> {
//        return Observable.create({ (observer) -> Disposable in
//            observer.onNext(.validating)
//
//            let session = HttpSession.post(urlString: urlString,
//                                           isJson: isJson,
//                                           params: params)
//
//            session.responseModelDict({ (models:[String:[M]]) in
//                observer.onNext(.success(model:ModelDictionary(models)))
//                observer.onCompleted()
//            }).error({ (error) in
//                observer.onNext(.failed(error:error.description))
//                observer.onCompleted()
//            })
//
//            return session
//        }).observeOn(MainScheduler.instance)
//    }
//
////    static func post<M:Model>(urlString:String,
////                    params:Any? = nil) -> Observable<APIItem<ModelList<M>>> {
////        return Observable.create({ (observer) -> Disposable in
////            observer.onNext(.validating)
////
////            let session = HttpSession.post(urlString: urlString,
////                                           params: params)
////
////            session.responseModelList({ (models:[M]) in
////                observer.onNext(.success(model:ModelList(models)))
////                observer.onCompleted()
////            }).error({ (error) in
////                observer.onNext(.failed(error:error.description))
////            })
////
////            return session
////        }).observeOn(MainScheduler.instance)
////    }
//}

fileprivate extension Date {
    init?(fromString string: String, format: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        if let date = formatter.date(from: string) {
            self = date
        } else {
            return nil
        }
    }
}

fileprivate extension String {
    func toFloat() -> Float? {
        if let num = NumberFormatter().number(from: self) {
            return num.floatValue
        } else {
            return nil
        }
    }
    
    func toDouble() -> Double? {
        if let num = NumberFormatter().number(from: self) {
            return num.doubleValue
        } else {
            return nil
        }
    }
    
    func isNumber() -> Bool {
        let scan = Scanner(string: self)
        
        var val:Int = 0
        
        return scan.scanInt(&val) && scan.isAtEnd
    }
}
