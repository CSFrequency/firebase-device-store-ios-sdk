# Firebase Device Store (iOS SDK)

Automatically store Device and FCM Token information for Firebase Auth Users in Cloud Firestore.

> This library is a proof of concept, and very much a work in progress.

## Installation

TODO

## Example usage

TODO

## Documentation

Firebase Device Store automatically stores device and FCM information for Firebase Auth users in Cloud Firestore.

### Data Model

A Document is created in the Cloud Firestore collection for each logged in user:

```
/user-devices
  - userId1: {},
  - userId2: {},
```

The structure of this Document is as follows:

```
{
  devices: {
    deviceId1: Device,
    deviceId2: Device,
    ...
  },
  userId: string,
}
```

A `Device` object contains the following:

```
{
  deviceId: string, // A UUID for the device
  fcmToken: string, // The FCM token
  name: string,     // The name of the device (e.g. 'Bob's iPhone')
  os: string,       // The OS of the device
  type: 'iOS'
}
```

### API

#### `FirebaseDeviceStore(app, collectionPath)`

Create a new DeviceStore.

Parameters:

- `app`: `FirebaseApp` the Firebase App to use.
- `collectionPath`: (Optional) `string` the Cloud Firestore collection where devices should be stored. Defaults to `user-devices`.

Returns a `FirebaseDeviceStore`.

#### `FirebaseDeviceStore.signOut(completion: (Bool, Error?) -> Void): void`

Indicate to the DeviceStore that the user is about to sign out, and the current device token should be removed.

This can't be done automatically with `onAuthStateChanged` as the user is already signed out at this point. This means the Cloud Firestore security rules will prevent the database deletion as they no longer have the correct user permissions to remove the token.

Parameters:

- `completion`: `(Bool, Error?) -> Void` a callback handler which will return a `boolean` to indicate if the subscription succeed, as well as an `Error` if it did not

#### `FirebaseDeviceStore.subscribe(completion: (Bool, Error?) -> Void): void`

Subscribe a device store to the Firebase App. This will:

1. Request appropriate Notification permissions, if they have not already been granted
2. Subscribe to Firebase Auth and listen to changes in authentication state
3. Subscribe to Firebase Messaging and listen to changes in the FCM token
4. Automatically store device and FCM token information in the Cloud Firestore collection you specify

Parameters:

- `completion`: `(Bool, Error?) -> Void` a callback handler which will return a `boolean` to indicate if the subscription succeed, as well as an `Error` if it did not

#### `FirebaseDeviceStore.unsubscribe(): void`

Unsubscribe the device store from the Firebase App.

### Security rules

You will need to add the following security rules for your Cloud Firestore collection:

```
service cloud.firestore {
  match /databases/{database}/documents {
    // Add this rule, replacing `user-devices` with the collection path you would like to use:
    match /user-devices/{userId} {
      allow create, read, update, delete: if request.auth.uid == userId;
    }
  }
}
```
