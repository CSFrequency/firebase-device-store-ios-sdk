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
            updateDevice(currentUser!.uid, fcmToken, completion: {_ in });
        }
        // Update the cached token
        currentToken = fcmToken;
    }

    public func signOut(_ completion: @escaping (Bool, Error?) -> Void) {
        if (currentUser != nil && currentToken != nil) {
            // Store the UID before we clear the user
            let uid = currentUser!.uid;
            currentUser = nil;
            return deleteDevice(uid, completion: { (error) in
                completion(error == nil, error);
            });
        }
        // Clear the cached user
        currentUser = nil;
        return completion(true, nil);
    }

    public func subscribe(_ completion: @escaping (Bool, Error?) -> Void) {
        // Prevent duplicate subscriptions
        if (subscribed) {
            completion(true, nil);
            return;
        }

        // Check notification permissions
        let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
        UNUserNotificationCenter.current().requestAuthorization(options: authOptions) { (authorized, error) in
            if (!authorized) {
                completion(false, error);
            } else {
                self.doSubscribe();
                completion(true, nil);
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
                    self.updateDevice(self.currentUser!.uid, self.currentToken!, completion: {_ in });
                }
            }
        }

        authSubscription = auth.addStateDidChangeListener { (auth, user) in
            if (user != nil && self.currentUser == nil) {
                self.currentUser = user;
                
                if (self.currentToken != nil) {
                    self.updateDevice(self.currentUser!.uid, self.currentToken!, completion: {_ in });
                }
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

    private func deleteDevice(_ userId: String, completion: @escaping (Error?) -> Void) {
        let docRef = userRef(userId);

        docRef.getDocument { (doc, error) in
            if (doc != nil) {
                if (doc!.exists) {
                    return docRef.updateData([FieldPath.init([self.DEVICES_FIELD, self.getDeviceId()]): FieldValue.delete()], completion: completion);
                }
                return completion(nil);
            }
            return completion(error);
        }
    }

    private func updateDevice(_ userId: String, _ token: String, completion: @escaping (Error?) -> Void) {
        let docRef = userRef(userId);

        docRef.getDocument { (doc, error) in
            if (doc != nil) {
                if (doc!.exists) {
                    let deviceId = self.getDeviceId();
                    return docRef.updateData([FieldPath.init([self.DEVICES_FIELD, self.getDeviceId()]): self.createDevice(deviceId, token)], completion: completion);
                } else {
                    return docRef.setData(self.createUserDevices(userId, token), completion: completion);
                }
            }
            return completion(error);
        }
    }

    private func createDevice(_ deviceId: String, _ token: String) -> [String: String] {
        let device: [String: String] = [
            DEVICE_ID_FIELD: deviceId,
            FCM_TOKEN_FIELD: token,
            NAME_FIELD: getDeviceName(),
            OS_FIELD: getOS(),
            TYPE_FIELD: "iOS"
        ];
        return device;
    }

    private func createUserDevices(_ userId: String, _ token: String) -> [String: Any] {
        let deviceId = getDeviceId();
        let devices: [String: [String: String]] = [deviceId: createDevice(deviceId, token)];
        
        let userDevices: [String: Any] = [
            DEVICES_FIELD: devices,
            USER_ID_FIELD: userId,
        ];
        return userDevices;
    }

    private func getDeviceId() -> String {
        return UIDevice.current.identifierForVendor!.uuidString;
    }

    private func getDeviceName() -> String {
        return UIDevice.current.name;
    }

    private func getOS() -> String {
        return "iOS " + UIDevice.current.systemVersion;
    }

    private func userRef(_ userId: String) -> DocumentReference {
        return firestore.collection(collectionPath).document(userId);
    }
}
