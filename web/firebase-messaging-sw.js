// Firebase Cloud Messaging Service Worker
// This file handles background push notifications for web

importScripts('https://www.gstatic.com/firebasejs/10.7.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.7.0/firebase-messaging-compat.js');

firebase.initializeApp({
    apiKey: 'AIzaSyD3nIWOdtwNuSkggGs_4Du_rsfvsd7qHxo',
    authDomain: 'bandroadie-65b18.firebaseapp.com',
    projectId: 'bandroadie-65b18',
    storageBucket: 'bandroadie-65b18.firebasestorage.app',
    messagingSenderId: '119100589120',
    appId: '1:119100589120:web:efcfb0cdf1501488c3cba5',
    measurementId: 'G-QFC8JXHKDC',
});

const messaging = firebase.messaging();

// Handle background messages
messaging.onBackgroundMessage((payload) => {
    console.log('[firebase-messaging-sw.js] Received background message:', payload);

    const notificationTitle = payload.notification?.title || 'Band Roadie';
    const notificationOptions = {
        body: payload.notification?.body || '',
        icon: '/icons/Icon-192.png',
        badge: '/icons/Icon-192.png',
        data: payload.data,
        // Tag to replace existing notification with same tag
        tag: payload.data?.notification_id || 'default',
    };

    return self.registration.showNotification(notificationTitle, notificationOptions);
});

// Handle notification click
self.addEventListener('notificationclick', (event) => {
    console.log('[firebase-messaging-sw.js] Notification clicked:', event);

    event.notification.close();

    // Get deep link from notification data
    const deepLink = event.notification.data?.deep_link;
    const urlToOpen = deepLink ? new URL(deepLink, self.location.origin).href : '/';

    event.waitUntil(
        clients.matchAll({ type: 'window', includeUncontrolled: true }).then((windowClients) => {
            // Check if app is already open
            for (let i = 0; i < windowClients.length; i++) {
                const client = windowClients[i];
                if (client.url.includes(self.location.origin) && 'focus' in client) {
                    // Navigate existing window to deep link
                    client.postMessage({
                        type: 'NOTIFICATION_CLICK',
                        deepLink: deepLink,
                    });
                    return client.focus();
                }
            }
            // Open new window if app not open
            if (clients.openWindow) {
                return clients.openWindow(urlToOpen);
            }
        })
    );
});
