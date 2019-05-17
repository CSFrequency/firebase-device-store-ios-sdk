import Foundation
import UserNotifications

import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import FirebaseInstanceID
import FirebaseMessaging

public class FirebaseDeviceStore: NSObject, MessagingDelegate {
    private let DEFAULT_COLLECTION_PATH: String = "user-devices"
    private let DEVICE_ID_FIELD: String = "deviceId"
    private let DEVICES_FIELD: String = "devices"
    private let FCM_TOKEN_FIELD: String = "fcmToken"
    private let NAME_FIELD: String = "name";
    private let OS_FIELD: String = "os";
    private let TYPE_FIELD: String = "type";
    private let USER_ID_FIELD: String = "userId";

    private let auth: Auth
    private let collectionPath: String
    private let firestore: Firestore
    private let instanceId: InstanceID

    private var authSubscription: AuthStateDidChangeListenerHandle?;
    private var currentToken: String?
    private var currentUser: User?
    private var subscribed: Bool = false

    public init(app: FirebaseApp, collectionPath: String = "user-devices") {
        self.auth = Auth.auth(app: app);
        self.collectionPath = collectionPath;
        self.firestore = Firestore.firestore(app: app);
        self.instanceId = InstanceID.instanceID();

        super.init();
        Messaging.messaging().delegate = self;
    }

    // FIRMessaging delegate implementation
    public func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String) {
        // Ignore token changes if the store isn't subscribed
        if (!subscribed) {
            return;
        }
        // If the token has changed, then update it
        if (fcmToken != currentToken && currentUser != nil) {
            updateDevice(currentUser!.uid, fcmToken);
        }
        // Update the cached token
        currentToken = fcmToken;
    }

    public func signOut() {
        if (currentUser != nil && currentToken != nil) {
            deleteDevice(currentUser!.uid);
        }
        // Clear the cached user
        currentUser = nil;
    }

    public func subscribe(_ handler: @escaping (Bool) -> Void) {
        if (subscribed) {
            return;
        }

        // Check notification permissions
        let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
        UNUserNotificationCenter.current().requestAuthorization(options: authOptions) { (authorized, error) in
            if (!authorized) {
                handler(false);
            } else {
                self.doSubscribe();
                handler(true);
            }
        }
    }

    private func doSubscribe() {
        subscribed = true;

        currentUser = auth.currentUser;

        instanceId.instanceID { (result, error) in
            if (error != nil) {
                // TODO: Logging
            } else if (result != nil) {
                self.currentToken = result!.token;

                if (self.currentToken != nil && self.currentUser != nil) {
                    self.updateDevice(self.currentUser!.uid, self.currentToken!);
                }
            }
        }

        authSubscription = auth.addStateDidChangeListener { (auth, user) in
            if (user != nil && self.currentUser == nil && self.currentToken != nil) {
                self.currentUser = user;

                self.updateDevice(self.currentUser!.uid, self.currentToken!);
            } else if (user == nil && self.currentUser != nil) {
                // TODO: Log Warning
                // You need to call the `logout` method on the DeviceStore before logging out the user

                // Clear the cached user
                self.currentUser = user;
            }
        }
    }

    public func unsubscribe() {
        if (authSubscription != nil) {
            auth.removeStateDidChangeListener(authSubscription!);
            authSubscription = nil;
        }
        // Reset state
        currentToken = nil;
        currentUser = nil;
        // Clear subscription flag
        subscribed = false;
    }

    private func deleteDevice(_ userId: String) {
        let docRef = userRef(userId);

        firestore.runTransaction({ (transaction, errorPointer) -> Any? in
            let doc: DocumentSnapshot;
            do {
                try doc = transaction.getDocument(docRef);
            } catch let fetchError as NSError {
                errorPointer?.pointee = fetchError
                return nil;
            }

            if (doc.exists) {
                var devices = self.getDevices(doc);
                // Remove the old device
                devices = self.removeCurrentDevice(devices);
                // Update the document
                transaction.updateData([self.DEVICES_FIELD: devices], forDocument: docRef);
            } else {
                let devices = self.createUserDevices(userId, nil);
                transaction.setData(devices, forDocument: docRef);
            }
            return nil;
        }) { (object, error) in
            // TODO: Logging
        }
    }

    private func updateDevice(_ userId: String, _ token: String) {
        let docRef = userRef(userId);

        firestore.runTransaction({ (transaction, errorPointer) -> Any? in
            let doc: DocumentSnapshot;
            do {
                try doc = transaction.getDocument(docRef);
            } catch let fetchError as NSError {
                errorPointer?.pointee = fetchError
                return nil;
            }
            if (doc.exists) {
                var devices = self.getDevices(doc);
                if (self.containsCurrentDevice(devices)) {
                    // Update the device token if it already exists
                    self.updateCurrentDevice(devices, token);
                } else {
                    devices.append(self.createCurrentDevice(token));
                }
                // Update the document
                transaction.updateData([self.DEVICES_FIELD: devices], forDocument: docRef);
            } else {
                let devices = self.createUserDevices(userId, token);
                transaction.setData(devices, forDocument: docRef);
            }
            return nil;
        }) { (object, error) in
            // TODO: Logging
        }
    }

    private func containsCurrentDevice(_ devices: [[String: String]]) -> Bool {
        let deviceId = getDeviceId();
        for device in devices {
            if (deviceId == device[DEVICE_ID_FIELD]) {
                return true;
            }
        }
        return false;
    }

    private func createCurrentDevice(_ token: String) -> [String: String] {
        let device: [String: String] = [
            DEVICE_ID_FIELD: getDeviceId(),
            FCM_TOKEN_FIELD: token,
            NAME_FIELD: getDeviceName(),
            OS_FIELD: getOS(),
            TYPE_FIELD: "iOS"
        ];
        return device;
    }

    private func createUserDevices(_ userId: String, _ token: String?) -> [String: Any] {
        let userDevices: [String: Any] = [
            DEVICES_FIELD: token == nil ? [] : [createCurrentDevice(token!)],
            USER_ID_FIELD: userId,
        ];
        return userDevices;
    }

    private func getDeviceId() -> String {
        return UIDevice.current.identifierForVendor!.uuidString;
    }

    private func getDevices(_ snapshot: DocumentSnapshot) -> [[String: String]] {
        let devices: [[String: String]]? = snapshot.get(DEVICES_FIELD) as? [[String : String]];
        return devices ?? [];
    }

    private func getDeviceName() -> String {
        return UIDevice.current.name;
    }

    private func getOS() -> String {
        return "iOS " + UIDevice.current.systemVersion;
    }

    private func removeCurrentDevice(_ devices: [[String: String]]) -> [[String: String]] {
        let deviceId = getDeviceId();
        return devices.filter({ (device: [String : String]) -> Bool in
            return deviceId != device[DEVICE_ID_FIELD];
        })
    }

    private func updateCurrentDevice(_ devices: [[String: String]], _ token: String) {
        let deviceId = getDeviceId();
        for var device in devices {
            if (deviceId == device[DEVICE_ID_FIELD]) {
                device[FCM_TOKEN_FIELD] = token;
            }
        }
    }

    private func userRef(_ userId: String) -> DocumentReference {
        return firestore.collection(collectionPath).document(userId);
    }
}
