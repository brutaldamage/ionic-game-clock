    //
//  WebServerPlugin.swift
//  App
//
//  Created by Drew on 11/22/18.
//

import Foundation
import Capacitor

@objc(WebServerPlugin)
public class WebServerPlugin: CAPPlugin {
    
    // Timeout in seconds
    let TIMEOUT: Int = 60 * 3 * 1000000
    
    var webServer: GCDWebServer = GCDWebServer()
    var responses = SynchronizedDictionary<AnyHashable,Any?>()
    var onRequestCommand: CAPPluginCall? = nil
    
    override public init!(bridge: CAPBridge!, pluginId: String!, pluginName: String!) {
        super.init(bridge: bridge, pluginId: pluginId, pluginName: pluginName)
        self.webServer = GCDWebServer()
        self.onRequestCommand = nil
        self.responses = SynchronizedDictionary<AnyHashable,Any?>()
        self.initHTTPRequestHandlers()
    }
    
    @objc func startServer(_ call: CAPPluginCall) {
        
        var port = 8080
        let portValue = call.getInt("port")
        if portValue != nil {
            port = portValue as! Int;
        }
        
        self.webServer.start(withPort: UInt(port), bonjourName: nil)
        

//        let pluginResult = CDVPluginResult(status: CDVCommandStatus_OK)
//        self.commandDelegate!.send(pluginResult, callbackId: command.callbackId)
        
//        let value = call.getString("value") ?? ""
        call.success([
            "status": "ok"
            ])
    }
    
    @objc func onRequest(_ call: CAPPluginCall) {
        self.onRequestCommand = call
        call.save()
    }
    
    @objc func sendResponse(_ call: CAPPluginCall) {

        let requestId = call.getString("requestId") as! String;
        
        let body = call.getString("body");
        let status = call.getInt("status");
        let headers = call.getObject("headers", defaultValue: Dictionary<String, String>())
        
        self.responses[requestId] = [
            "status": status,
            "body" : body,
            "headers" : headers
        ];
    }
    
    func initHTTPRequestHandlers() {
        self.webServer.addHandler(
            match: {
                (requestMethod, requestURL, requestHeaders, urlPath, urlQuery) -> GCDWebServerRequest? in
                return GCDWebServerDataRequest(method: requestMethod, url: requestURL, headers: requestHeaders, path: urlPath, query: urlQuery)
        },
            asyncProcessBlock: self.processRequest
        )
    }
    
    func processRequest(request: GCDWebServerRequest, completionBlock: GCDWebServerCompletionBlock) {
        var timeout = 0
        // Fetch data as GCDWebserverDataRequest
        let requestUUID = UUID().uuidString
        // Transform it into an dictionary for the javascript plugin
        let requestDict = self.requestToRequestDict(requestUUID: requestUUID, request: request)
        
        // Do a call to the onRequestCommand to inform the JS plugin
        if (self.onRequestCommand != nil) {
            
            self.onRequestCommand?.success(requestDict)
        }
        
        // Here we have to wait until the javascript block fetches the message and do a response
        while self.responses[requestUUID] == nil {
            timeout += 1000
            usleep(1000)
        }
        
        // We got the dict so put information in the response
        let responseDict = self.responses[requestUUID] as! Dictionary<AnyHashable, Any>
        let response = GCDWebServerDataResponse(text: responseDict["body"] as! String)
        response?.statusCode = responseDict["status"] as! Int
        
        for (key, value) in (responseDict["headers"] as! Dictionary<String, String>) {
            response?.setValue(value, forAdditionalHeader: key)
        }
        
        // Remove the handled response
        self.responses.removeValue(forKey: requestUUID)
        
        // Complete the async response
        completionBlock(response!)
    }
    
    func requestToRequestDict(requestUUID: String, request: GCDWebServerRequest) -> Dictionary<String, Any> {
        let dataRequest = request as! GCDWebServerDataRequest
        var body = ""
        
        if dataRequest.hasBody() {
            body = String(data: dataRequest.data, encoding: String.Encoding(rawValue: String.Encoding.utf8.rawValue)) ?? ""
        }
        
        return [
            "requestId": requestUUID,
            "body": body,
            "headers": dataRequest.headers,
            "method": dataRequest.method,
            "path": dataRequest.url.path,
            "query": dataRequest.url.query ?? ""
        ]
    }
}
