//
//  ApphudInternal.swift
//  subscriptionstest
//
//  Created by ren6 on 01/07/2019.
//  Copyright © 2019 apphud. All rights reserved.
//

import Foundation
import StoreKit

internal typealias HasPurchasesChanges = (hasSubscriptionChanges: Bool, hasNonRenewingChanges: Bool)

@available(iOS 11.2, *)
final class ApphudInternal: NSObject {

    internal static let shared = ApphudInternal()
    internal var httpClient: ApphudHttpClient?
    internal weak var delegate: ApphudDelegate?
    internal weak var uiDelegate: ApphudUIDelegate?

    // MARK: - Private properties
    private var userRegisteredCallbacks = [ApphudVoidCallback]()
    private var addedObservers = false
    private var allowIdentifyUser = true

    // MARK: - Receipt and products properties
    internal var productsFetchRetriesCount: Int = 0
    internal let maxNumberOfProductsFetchRetries: Int = 10

    internal var productGroupsFetchedCallbacks = [ApphudVoidCallback]()
    internal var storeKitProductsFetchedCallbacks = [ApphudVoidCallback]()
    internal var customProductsFetchedBlocks = [ApphudStoreKitProductsCallback]()
    internal var productGroups = [ApphudGroup]()
    internal var paywalls = [ApphudPaywall]()

    internal var submitReceiptRetriesCount: Int = 0
    internal var submitReceiptCallbacks = [ApphudErrorCallback?]()
    internal var restorePurchasesCallback: (([ApphudSubscription]?, [ApphudNonRenewingPurchase]?, Error?) -> Void)?
    internal var isSubmittingReceipt: Bool = false

    // MARK: - User registering properties
    internal var currentUser: ApphudUser?
    internal var currentDeviceID: String = ""
    internal var currentUserID: String = ""
    internal var setNeedsToUpdateUser: Bool = false {
        didSet {
            if setNeedsToUpdateUser {
                self.perform(#selector(updateCurrentUser), with: nil, afterDelay: 2.0)
            } else {
                NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(updateCurrentUser), object: nil)
            }
        }
    }
    internal var setNeedsToUpdateUserProperties: Bool = false {
        didSet {
            if setNeedsToUpdateUserProperties {
                self.perform(#selector(updateUserProperties), with: nil, afterDelay: 1.0)
            } else {
                NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(updateUserProperties), object: nil)
            }
        }
    }
    internal var pendingUserProperties = [ApphudUserProperty]()
    internal var lastCheckDate = Date()
    internal var userRegisterRetriesCount: Int = 0
    internal let maxNumberOfUserRegisterRetries: Int = 10
    internal var paywallEventsRetriesCount: Int = 0
    internal let maxNumberOfPaywallEventsRetries: Int = 25
    internal var isRegisteringUser = false {
        didSet {
            if isRegisteringUser {
                NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(registerUser), object: nil)
            }
        }
    }

    // MARK: - Advertising Identifier

    internal var advertisingIdentifier: String? {
        didSet {
            if advertisingIdentifier != nil {
                apphudLog("Received IDFA (\(advertisingIdentifier ?? ""), will submit soon.")
                apphudPerformOnMainThread {
                    self.setNeedsToUpdateUser = true
                }
            }
        }
    }

    // MARK: - Attribution properties
    internal var requiresReceiptSubmission: Bool {
        get {
            UserDefaults.standard.bool(forKey: "requiresReceiptSubmissionKey")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "requiresReceiptSubmissionKey")
        }
    }
    internal let didSubmitAppsFlyerAttributionKey = "didSubmitAppsFlyerAttributionKey"
    internal let didSubmitFacebookAttributionKey = "didSubmitFacebookAttributionKey"
    internal let didSubmitAdjustAttributionKey = "didSubmitAdjustAttributionKey"
    internal let didSubmitProductPricesKey = "didSubmitProductPricesKey"
    internal let submittedFirebaseIdKey = "submittedFirebaseIdKey"
    internal var didSubmitAppleAdsAttributionKey = "didSubmitAppleAdsAttributionKey"
    internal var isSendingAppsFlyer = false
    internal var isSendingAdjust = false
    internal var isFreshInstall = true
    
    internal var didSubmitAppsFlyerAttribution: Bool {
        get {
            UserDefaults.standard.bool(forKey: didSubmitAppsFlyerAttributionKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: didSubmitAppsFlyerAttributionKey)
        }
    }
    internal var didSubmitFacebookAttribution: Bool {
        get {
            UserDefaults.standard.bool(forKey: didSubmitFacebookAttributionKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: didSubmitFacebookAttributionKey)
        }
    }
    internal var didSubmitAdjustAttribution: Bool {
        get {
            UserDefaults.standard.bool(forKey: didSubmitAdjustAttributionKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: didSubmitAdjustAttributionKey)
        }
    }
    internal var didSubmitProductPrices: Bool {
        get {
            UserDefaults.standard.bool(forKey: didSubmitProductPricesKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: didSubmitProductPricesKey)
        }
    }
    internal var didSubmitAppleAdsAttribution: Bool {
        get {
            UserDefaults.standard.bool(forKey: didSubmitAppleAdsAttributionKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: didSubmitAppleAdsAttributionKey)
        }
    }
    internal var submittedFirebaseId: String? {
        get {
            UserDefaults.standard.string(forKey: submittedFirebaseIdKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: submittedFirebaseIdKey)
        }
    }

    // MARK: - Initialization

    internal func initialize(apiKey: String, inputUserID: String?, inputDeviceID: String? = nil, observerMode: Bool) {

        if httpClient == nil {
            ApphudStoreKitWrapper.shared.setupObserver()
            httpClient = ApphudHttpClient.shared
            httpClient!.apiKey = apiKey
            apphudLog("Started Apphud SDK (\(apphud_sdk_version))", forceDisplay: true)
        }

        guard allowIdentifyUser == true else {
            apphudLog("Abort initializing, because Apphud SDK already initialized. You can only call `Apphud.start()` once per app lifecycle. Or if `Apphud.logout()` was called previously.", forceDisplay: true)
            return
        }
        allowIdentifyUser = false

        identify(inputUserID: inputUserID, inputDeviceID: inputDeviceID, observerMode: observerMode)
    }

    internal func identify(inputUserID: String?, inputDeviceID: String? = nil, observerMode: Bool) {

        ApphudUtils.shared.storeKitObserverMode = observerMode

        var deviceID = ApphudKeychain.loadDeviceID()

        isFreshInstall = deviceID == nil
        
        if inputDeviceID?.count ?? 0 > 0 {
            deviceID = inputDeviceID
        }

        let generatedUUID: String = ApphudKeychain.generateUUID()

        if deviceID == nil {
            deviceID = generatedUUID
            ApphudKeychain.saveDeviceID(deviceID: deviceID!)
        }

        self.currentDeviceID = deviceID!

        self.currentUser = ApphudUser.fromCache()
        let userIDFromKeychain = ApphudKeychain.loadUserID()

        if inputUserID?.count ?? 0 > 0 {
            self.currentUserID = inputUserID!
        } else if let existingUserID = self.currentUser?.user_id {
            self.currentUserID = existingUserID
        } else if userIDFromKeychain != nil {
            self.currentUserID = userIDFromKeychain!
        } else {
            self.currentUserID = generatedUUID
        }

        if self.currentUserID != userIDFromKeychain {
            ApphudKeychain.saveUserID(userID: self.currentUserID)
        }

        self.productGroups = cachedGroups() ?? []
        self.paywalls = cachedPaywalls() ?? []
        
        DispatchQueue.main.async {
            self.continueToRegisteringUser()
        }
    }

    internal func logout() {
        ApphudUser.clearCache()
        ApphudKeychain.resetValues()
        allowIdentifyUser = true
        apphudLog("User logged out. Apphud SDK is uninitialized.", logLevel: .all)
    }

    internal func continueToRegisteringUser() {
        guard !isRegisteringUser else {return}
        isRegisteringUser = true
        continueToFetchProducts()
        registerUser()
    }
    
    @objc private func registerUser() {
        createOrGetUser(shouldUpdateUserID: true) { success, errorCode in

            self.isRegisteringUser = false
            self.setupObservers()
            self.checkPendingRules()
            
            if success {
                apphudLog("User successfully registered with id: \(self.currentUserID)", forceDisplay: true)
                self.performAllUserRegisteredBlocks()
                self.checkForUnreadNotifications()
                self.perform(#selector(self.forceSendAttributionDataIfNeeded), with: nil, afterDelay: 10.0)
            } else {
                self.scheduleUserRegistering(errorCode: errorCode)
            }
        }
    }

    private func scheduleUserRegistering(errorCode: Int) {
        guard httpClient != nil, httpClient!.canRetry else {
            return
        }
        guard userRegisterRetriesCount < maxNumberOfUserRegisterRetries else {
            apphudLog("Reached max number of user register retries \(userRegisterRetriesCount). Exiting..", forceDisplay: true)
            return
        }
        
        let noInternetError = errorCode == NSURLErrorNotConnectedToInternet
        let retryImmediately = errorCode == NSURLErrorRedirectToNonExistentLocation
        
        let delay: TimeInterval

        if retryImmediately {
            delay = 0.01
        } else if noInternetError {
            delay = 2.0
        } else {
            delay = 5.0
            userRegisterRetriesCount += 1
        }
        
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(registerUser), object: nil)
        perform(#selector(registerUser), with: nil, afterDelay: delay)
        apphudLog("Scheduled user register retry in \(delay) seconds.", forceDisplay: true)
    }

    // MARK: - Other

    private func setupObservers() {
        if !addedObservers {
            NotificationCenter.default.addObserver(self, selector: #selector(handleDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
            addedObservers = true
        }
    }

    private func checkPendingRules() {
        performWhenUserRegistered {
            ApphudRulesManager.shared.handlePendingAPSInfo()
        }
    }
    
    @objc private func handleDidBecomeActive() {

        let minCheckInterval: Double = 60

        checkPendingRules()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if self.currentUser == nil {
                self.continueToRegisteringUser()
            } else if Date().timeIntervalSince(self.lastCheckDate) > minCheckInterval {
                self.checkForUnreadNotifications()
                self.updateCurrentUser()
            }
        }
    }

    // MARK: - Perform Blocks

    /// Returns false if current user is not yet registered, block is added to array and will be performed later.
    @discardableResult internal func performWhenUserRegistered(callback : @escaping ApphudVoidCallback) -> Bool {
        if currentUser != nil {
            callback()
            return true
        } else {
            userRegisteredCallbacks.append(callback)
            return false
        }
    }

    private func performAllUserRegisteredBlocks() {
        for block in userRegisteredCallbacks {
            apphudLog("Performing scheduled block..")
            block()
        }
        if userRegisteredCallbacks.count > 0 {
            apphudLog("All scheduled blocks performed, removing..")
            userRegisteredCallbacks.removeAll()
        }
    }

    /// Returns false if products groups map dictionary not yet received, block is added to array and will be performed later.
    @discardableResult internal func performWhenProductGroupsFetched(callback : @escaping ApphudVoidCallback) -> Bool {
        if self.productGroups.count > 0 {
            callback()
            return true
        } else {
            productGroupsFetchedCallbacks.append(callback)
            return false
        }
    }

    internal func performAllProductGroupsFetchedCallbacks() {
        for block in productGroupsFetchedCallbacks {
            apphudLog("Performing scheduled block..")
            block()
        }
        if productGroupsFetchedCallbacks.count > 0 {
            apphudLog("All scheduled blocks performed, removing..")
            productGroupsFetchedCallbacks.removeAll()
        }
    }
    
    /// Returns false if products groups map dictionary not yet received, block is added to array and will be performed later.
    @discardableResult internal func performWhenStoreKitProductFetched(callback : @escaping ApphudVoidCallback) -> Bool {
        if ApphudStoreKitWrapper.shared.didFetch {
            callback()
            return true
        } else {
            storeKitProductsFetchedCallbacks.append(callback)
            return false
        }
    }
    
    internal func performAllStoreKitProductsFetchedCallbacks() {
        for block in storeKitProductsFetchedCallbacks {
            apphudLog("Performing scheduled block..")
            block()
        }
        if storeKitProductsFetchedCallbacks.count > 0 {
            apphudLog("All scheduled blocks performed, removing..")
            storeKitProductsFetchedCallbacks.removeAll()
        }
    }

    // MARK: - Push Notifications API

    internal func submitPushNotificationsToken(token: Data, callback: ApphudBoolCallback?) {
        performWhenUserRegistered {
            let tokenString = token.map { String(format: "%02.2hhx", $0) }.joined()
            let params: [String: String] = ["device_id": self.currentDeviceID, "push_token": tokenString]
            self.httpClient?.startRequest(path: "customers/push_token", params: params, method: .put) { (result, _, _, _, _) in
                callback?(result)
            }
        }
    }

    // MARK: - V2 API

    internal func trackEvent(params: [String: AnyHashable], callback: @escaping () -> Void) {
        let result = performWhenUserRegistered {
            let final_params: [String: AnyHashable] = ["device_id": self.currentDeviceID].merging(params, uniquingKeysWith: {(current, _) in current})
            self.httpClient?.startRequest(path: "events", apiVersion: .APIV2, params: final_params, method: .post) { (_, _, _, _, _) in
                callback()
            }
        }
        if !result {
            apphudLog("Tried to trackRuleEvent, but user not yet registered, adding to schedule")
        }
    }
    
    @objc internal func trackPaywallEvent(params: [String: AnyHashable]) {
        submitPaywallEvent(params: params) { (result, _, _, _, code) in
            if !result {
                self.schedulePaywallEvent(params, code == NSURLErrorNotConnectedToInternet)
            }
        }
    }
    
    private func schedulePaywallEvent(_ params: [String: AnyHashable], _ noInternetError: Bool) {
        guard httpClient != nil, httpClient!.canRetry else {
            return
        }
        guard paywallEventsRetriesCount < maxNumberOfPaywallEventsRetries else {
            apphudLog("Reached max number of paywall events retries \(paywallEventsRetriesCount). Exiting..", forceDisplay: true)
            return
        }
        
        let delay: TimeInterval

        if noInternetError {
            delay = 2.0
        } else {
            delay = 5.0
            paywallEventsRetriesCount += 1
        }
        
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(trackPaywallEvent(params:)), object: nil)
        perform(#selector(trackPaywallEvent(params:)), with: params, afterDelay: delay)
        apphudLog("Scheduled paywall events retry in \(delay) seconds.", forceDisplay: true)
    }
    
    internal func submitPaywallEvent(params: [String: AnyHashable], callback: @escaping ApphudHTTPResponseCallback) {
        let result = performWhenUserRegistered {
            let environment = Apphud.isSandbox() ? "sandbox" : "production"
            let final_params: [String: AnyHashable] = ["device_id": self.currentDeviceID,
                                                       "user_id": self.currentUserID,
                                                       "timestamp": Date().currentTimestamp(),
                                                       "environment": environment].merging(params, uniquingKeysWith: {(current, _) in current})
            
            self.httpClient?.startRequest(path: "events", apiVersion: .APIV1, params: final_params, method: .post, callback: callback)
        }
        if !result {
            apphudLog("Tried to trackPaywallEvent, but user not yet registered, adding to schedule")
        }
    }
    
    internal func logEvent(params: [String: AnyHashable], callback: @escaping () -> Void) {

        let result = performWhenUserRegistered {
            let environment = Apphud.isSandbox() ? "sandbox" : "production"
            var final_params: [String: AnyHashable] = ["device_id": self.currentDeviceID,
                                                       "user_id": self.currentUserID,
                                                       "timestamp": Date().currentTimestamp(),
                                                       "environment": environment].merging(params, uniquingKeysWith: {(current, _) in current})
            
            if let bundleID = Bundle.main.bundleIdentifier {
                final_params["bundle_id"] = bundleID
            }
            
            self.httpClient?.startRequest(path: "logs", apiVersion: .APIV1, params: final_params, method: .post) { (_, _, _, _, _) in
                callback()
            }
        }
        if !result {
            apphudLog("Tried to trackPaywallEvent, but user not yet registered, adding to schedule")
        }
    }

    /// Not used yet
    internal func getRule(ruleID: String, callback: @escaping (ApphudRule?) -> Void) {

        let result = performWhenUserRegistered {
            let params = ["device_id": self.currentDeviceID] as [String: String]

            self.httpClient?.startRequest(path: "rules/\(ruleID)", apiVersion: .APIV2, params: params, method: .get) { (result, response, _, _, _) in
                if result, let dataDict = response?["data"] as? [String: Any],
                    let ruleDict = dataDict["results"] as? [String: Any] {
                    callback(ApphudRule(dictionary: ruleDict))
                } else {
                    callback(nil)
                }
            }
        }
        if !result {
            apphudLog("Tried to getRule \(ruleID), but user not yet registered, adding to schedule")
        }
    }

    internal func checkForUnreadNotifications() {
        performWhenUserRegistered {
            let params = ["device_id": self.currentDeviceID] as [String: String]
            self.httpClient?.startRequest(path: "notifications", apiVersion: .APIV2, params: params, method: .get, callback: { (result, response, _, _, _) in

                if result, let dataDict = response?["data"] as? [String: Any], let notifArray = dataDict["results"] as? [[String: Any]], let notifDict = notifArray.first, var ruleDict = notifDict["rule"] as? [String: Any] {
                    let properties = notifDict["properties"] as? [String: Any]
                    ruleDict = ruleDict.merging(properties ?? [:], uniquingKeysWith: {_, new in new})
                    let rule = ApphudRule(dictionary: ruleDict)
                    ApphudRulesManager.shared.handleRule(rule: rule)
                }
            })
        }
    }

    internal func readAllNotifications(for ruleID: String) {
        performWhenUserRegistered {
            let params = ["device_id": self.currentDeviceID, "rule_id": ruleID] as [String: String]
            self.httpClient?.startRequest(path: "notifications/read", apiVersion: .APIV2, params: params, method: .post, callback: { (_, _, _, _, _) in
            })
        }
    }
    
    internal func getActiveRuleScreens(_ callback: @escaping ([String]) -> Void) {
        performWhenUserRegistered {
            self.httpClient?.startRequest(path: "rules/screens", apiVersion: .APIV2, params: nil, method: .get) { result, response, _, error, code in
                if result, let dataDict = response?["data"] as? [String: Any], let screensIdsArray = dataDict["results"] as? [String] {
                    callback(screensIdsArray)
                } else {
                    callback([])
                }
            }
        }
    }
}

extension Date {
    func currentTimestamp() -> Int64 {
        return Int64(self.timeIntervalSince1970 * 1000)
    }
}
