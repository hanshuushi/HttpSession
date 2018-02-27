//
//  URLConfigProtocol.swift
//  HttpSession
//
//  Created by 范舟弛 on 2018/2/27.
//

import Foundation

/// URL 配置相关
protocol URLConfig {
    
    /// API URL前缀
    var baseURL: String { get }
    
    /// 图片 URL前缀
    var basePicURL: String { get }
    
    /// 版本号请求在Header上的Key
    var versionKeyInHeader: String { get }
    
    /// 返回数据的Key
    var responseDataKey: (code: String, message: String, data: String) { get }
}

extension URLConfig {
    /// 当前版本号
    var version: String {
        let infoDictionary = Bundle.main.infoDictionary
        
        return (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.1.0"
    }
}
