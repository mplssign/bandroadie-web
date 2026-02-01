'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"flutter_bootstrap.js": "212ec819f023c22ca58da0aca6a131b8",
"version.json": "47e1d14cf2586e0850f1ad067dcd72d7",
"index.html": "fb587f8a2544c36efd6f71f5b91377ac",
"/": "fb587f8a2544c36efd6f71f5b91377ac",
"app/flutter_bootstrap.js": "2db05134d4d1ef7071935d372c1fdef0",
"app/version.json": "47e1d14cf2586e0850f1ad067dcd72d7",
"app/index.html": "fb587f8a2544c36efd6f71f5b91377ac",
"app/app/flutter_bootstrap.js": "15d05b7a1b3b3768f35125371d4e6180",
"app/app/version.json": "47e1d14cf2586e0850f1ad067dcd72d7",
"app/app/index.html": "fb587f8a2544c36efd6f71f5b91377ac",
"app/app/firebase-messaging-sw.js": "406c31f9d237c56c8c1fc8ceb75b6b5d",
"app/app/support.html": "a9a4b6f8216bfba4a17db941cc37bdd9",
"app/app/main.dart.js": "c7a42f5ebe7510ce612adcd04ad12890",
"app/app/flutter.js": "24bc71911b75b5f8135c949e27a2984e",
"app/app/favicon.png": "db652681fa5504c0a0027bbf8a3a2329",
"app/app/icons/Icon-192.png": "db652681fa5504c0a0027bbf8a3a2329",
"app/app/icons/Icon-maskable-192.png": "db652681fa5504c0a0027bbf8a3a2329",
"app/app/icons/Icon-maskable-512.png": "56814cfb51ad91c2895c3c777143dffa",
"app/app/icons/Icon-512.png": "56814cfb51ad91c2895c3c777143dffa",
"app/app/manifest.json": "a3999474f59d1e90056a189cffef9495",
"app/app/assets/NOTICES": "c501b8274ec9238e6b390c0bf5290902",
"app/app/assets/FontManifest.json": "dc3d03800ccca4601324923c0b1d6d57",
"app/app/assets/AssetManifest.bin.json": "ab1ba3db62275aa1f1262079cf53dedd",
"app/app/assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "33b7d9392238c04c131b6ce224e13711",
"app/app/assets/shaders/ink_sparkle.frag": "ecc85a2e95f5e9f53123dcaf8cb9b6ce",
"app/app/assets/shaders/stretch_effect.frag": "40d68efbbf360632f614c731219e95f0",
"app/app/assets/AssetManifest.bin": "52eae82e8635d12a651e42a415a3ccd9",
"app/app/assets/fonts/MaterialIcons-Regular.otf": "d2334b5cfab491c22e497f78f95c7a69",
"app/app/assets/assets/images/bandroadie_logo.svg": "4c741828c86285636edbc99632adea01",
"app/app/assets/assets/images/band_roadie_logo_tagline.svg": "e903b5bce1f558e1fd828a42163d0ea7",
"app/app/assets/assets/images/phone_dashboard.png": "86d1af76906da39d0702abf3e675c5a4",
"app/app/assets/assets/images/bandroadie_logo_optimized.svg": "8103588d4e137e63ec120bc5d941ca1b",
"app/app/assets/assets/images/phone_hands.png": "c7a149a88f20e16a2df801d7d00619bb",
"app/app/privacy.html": "49bfaba113dd4a469f365f9704ea7ee5",
"app/app/canvaskit/skwasm.js": "8060d46e9a4901ca9991edd3a26be4f0",
"app/app/canvaskit/skwasm_heavy.js": "740d43a6b8240ef9e23eed8c48840da4",
"app/app/canvaskit/skwasm.js.symbols": "3a4aadf4e8141f284bd524976b1d6bdc",
"app/app/canvaskit/canvaskit.js.symbols": "a3c9f77715b642d0437d9c275caba91e",
"app/app/canvaskit/skwasm_heavy.js.symbols": "0755b4fb399918388d71b59ad390b055",
"app/app/canvaskit/skwasm.wasm": "7e5f3afdd3b0747a1fd4517cea239898",
"app/app/canvaskit/chromium/canvaskit.js.symbols": "e2d09f0e434bc118bf67dae526737d07",
"app/app/canvaskit/chromium/canvaskit.js": "a80c765aaa8af8645c9fb1aae53f9abf",
"app/app/canvaskit/chromium/canvaskit.wasm": "a726e3f75a84fcdf495a15817c63a35d",
"app/app/canvaskit/canvaskit.js": "8331fe38e66b3a898c4f37648aaf7ee2",
"app/app/canvaskit/canvaskit.wasm": "9b6a7830bf26959b200594729d73538e",
"app/app/canvaskit/skwasm_heavy.wasm": "b0be7910760d205ea4e011458df6ee01",
"app/vercel.json": "198a110c6ed426a6a64d247f6569646c",
"app/firebase-messaging-sw.js": "406c31f9d237c56c8c1fc8ceb75b6b5d",
"app/support.html": "a9a4b6f8216bfba4a17db941cc37bdd9",
"app/main.dart.js": "c7a42f5ebe7510ce612adcd04ad12890",
"app/flutter.js": "24bc71911b75b5f8135c949e27a2984e",
"app/favicon.png": "db652681fa5504c0a0027bbf8a3a2329",
"app/icons/Icon-192.png": "db652681fa5504c0a0027bbf8a3a2329",
"app/icons/Icon-maskable-192.png": "db652681fa5504c0a0027bbf8a3a2329",
"app/icons/Icon-maskable-512.png": "56814cfb51ad91c2895c3c777143dffa",
"app/icons/Icon-512.png": "56814cfb51ad91c2895c3c777143dffa",
"app/manifest.json": "a3999474f59d1e90056a189cffef9495",
"app/assets/NOTICES": "c501b8274ec9238e6b390c0bf5290902",
"app/assets/FontManifest.json": "dc3d03800ccca4601324923c0b1d6d57",
"app/assets/AssetManifest.bin.json": "ab1ba3db62275aa1f1262079cf53dedd",
"app/assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "33b7d9392238c04c131b6ce224e13711",
"app/assets/shaders/ink_sparkle.frag": "ecc85a2e95f5e9f53123dcaf8cb9b6ce",
"app/assets/shaders/stretch_effect.frag": "40d68efbbf360632f614c731219e95f0",
"app/assets/AssetManifest.bin": "52eae82e8635d12a651e42a415a3ccd9",
"app/assets/fonts/MaterialIcons-Regular.otf": "d2334b5cfab491c22e497f78f95c7a69",
"app/assets/assets/images/bandroadie_logo.svg": "4c741828c86285636edbc99632adea01",
"app/assets/assets/images/band_roadie_logo_tagline.svg": "e903b5bce1f558e1fd828a42163d0ea7",
"app/assets/assets/images/phone_dashboard.png": "86d1af76906da39d0702abf3e675c5a4",
"app/assets/assets/images/bandroadie_logo_optimized.svg": "8103588d4e137e63ec120bc5d941ca1b",
"app/assets/assets/images/phone_hands.png": "c7a149a88f20e16a2df801d7d00619bb",
"app/privacy.html": "49bfaba113dd4a469f365f9704ea7ee5",
"app/canvaskit/skwasm.js": "8060d46e9a4901ca9991edd3a26be4f0",
"app/canvaskit/skwasm_heavy.js": "740d43a6b8240ef9e23eed8c48840da4",
"app/canvaskit/skwasm.js.symbols": "3a4aadf4e8141f284bd524976b1d6bdc",
"app/canvaskit/canvaskit.js.symbols": "a3c9f77715b642d0437d9c275caba91e",
"app/canvaskit/skwasm_heavy.js.symbols": "0755b4fb399918388d71b59ad390b055",
"app/canvaskit/skwasm.wasm": "7e5f3afdd3b0747a1fd4517cea239898",
"app/canvaskit/chromium/canvaskit.js.symbols": "e2d09f0e434bc118bf67dae526737d07",
"app/canvaskit/chromium/canvaskit.js": "a80c765aaa8af8645c9fb1aae53f9abf",
"app/canvaskit/chromium/canvaskit.wasm": "a726e3f75a84fcdf495a15817c63a35d",
"app/canvaskit/canvaskit.js": "8331fe38e66b3a898c4f37648aaf7ee2",
"app/canvaskit/canvaskit.wasm": "9b6a7830bf26959b200594729d73538e",
"app/canvaskit/skwasm_heavy.wasm": "b0be7910760d205ea4e011458df6ee01",
"vercel.json": "198a110c6ed426a6a64d247f6569646c",
"firebase-messaging-sw.js": "406c31f9d237c56c8c1fc8ceb75b6b5d",
"support.html": "a9a4b6f8216bfba4a17db941cc37bdd9",
"main.dart.js": "c7a42f5ebe7510ce612adcd04ad12890",
"flutter.js": "24bc71911b75b5f8135c949e27a2984e",
"favicon.png": "db652681fa5504c0a0027bbf8a3a2329",
"icons/Icon-192.png": "db652681fa5504c0a0027bbf8a3a2329",
"icons/Icon-maskable-192.png": "db652681fa5504c0a0027bbf8a3a2329",
"icons/Icon-maskable-512.png": "56814cfb51ad91c2895c3c777143dffa",
"icons/Icon-512.png": "56814cfb51ad91c2895c3c777143dffa",
"manifest.json": "a3999474f59d1e90056a189cffef9495",
"assets/NOTICES": "c501b8274ec9238e6b390c0bf5290902",
"assets/FontManifest.json": "dc3d03800ccca4601324923c0b1d6d57",
"assets/AssetManifest.bin.json": "ab1ba3db62275aa1f1262079cf53dedd",
"assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "33b7d9392238c04c131b6ce224e13711",
"assets/shaders/ink_sparkle.frag": "ecc85a2e95f5e9f53123dcaf8cb9b6ce",
"assets/shaders/stretch_effect.frag": "40d68efbbf360632f614c731219e95f0",
"assets/AssetManifest.bin": "52eae82e8635d12a651e42a415a3ccd9",
"assets/fonts/MaterialIcons-Regular.otf": "d2334b5cfab491c22e497f78f95c7a69",
"assets/assets/images/bandroadie_logo.svg": "4c741828c86285636edbc99632adea01",
"assets/assets/images/band_roadie_logo_tagline.svg": "e903b5bce1f558e1fd828a42163d0ea7",
"assets/assets/images/phone_dashboard.png": "86d1af76906da39d0702abf3e675c5a4",
"assets/assets/images/bandroadie_logo_optimized.svg": "8103588d4e137e63ec120bc5d941ca1b",
"assets/assets/images/phone_hands.png": "c7a149a88f20e16a2df801d7d00619bb",
"privacy.html": "49bfaba113dd4a469f365f9704ea7ee5",
"canvaskit/skwasm.js": "8060d46e9a4901ca9991edd3a26be4f0",
"canvaskit/skwasm_heavy.js": "740d43a6b8240ef9e23eed8c48840da4",
"canvaskit/skwasm.js.symbols": "3a4aadf4e8141f284bd524976b1d6bdc",
"canvaskit/canvaskit.js.symbols": "a3c9f77715b642d0437d9c275caba91e",
"canvaskit/skwasm_heavy.js.symbols": "0755b4fb399918388d71b59ad390b055",
"canvaskit/skwasm.wasm": "7e5f3afdd3b0747a1fd4517cea239898",
"canvaskit/chromium/canvaskit.js.symbols": "e2d09f0e434bc118bf67dae526737d07",
"canvaskit/chromium/canvaskit.js": "a80c765aaa8af8645c9fb1aae53f9abf",
"canvaskit/chromium/canvaskit.wasm": "a726e3f75a84fcdf495a15817c63a35d",
"canvaskit/canvaskit.js": "8331fe38e66b3a898c4f37648aaf7ee2",
"canvaskit/canvaskit.wasm": "9b6a7830bf26959b200594729d73538e",
"canvaskit/skwasm_heavy.wasm": "b0be7910760d205ea4e011458df6ee01"};
// The application shell files that are downloaded before a service worker can
// start.
const CORE = ["main.dart.js",
"index.html",
"flutter_bootstrap.js",
"assets/AssetManifest.bin.json",
"assets/FontManifest.json"];

// During install, the TEMP cache is populated with the application shell files.
self.addEventListener("install", (event) => {
  self.skipWaiting();
  return event.waitUntil(
    caches.open(TEMP).then((cache) => {
      return cache.addAll(
        CORE.map((value) => new Request(value, {'cache': 'reload'})));
    })
  );
});
// During activate, the cache is populated with the temp files downloaded in
// install. If this service worker is upgrading from one with a saved
// MANIFEST, then use this to retain unchanged resource files.
self.addEventListener("activate", function(event) {
  return event.waitUntil(async function() {
    try {
      var contentCache = await caches.open(CACHE_NAME);
      var tempCache = await caches.open(TEMP);
      var manifestCache = await caches.open(MANIFEST);
      var manifest = await manifestCache.match('manifest');
      // When there is no prior manifest, clear the entire cache.
      if (!manifest) {
        await caches.delete(CACHE_NAME);
        contentCache = await caches.open(CACHE_NAME);
        for (var request of await tempCache.keys()) {
          var response = await tempCache.match(request);
          await contentCache.put(request, response);
        }
        await caches.delete(TEMP);
        // Save the manifest to make future upgrades efficient.
        await manifestCache.put('manifest', new Response(JSON.stringify(RESOURCES)));
        // Claim client to enable caching on first launch
        self.clients.claim();
        return;
      }
      var oldManifest = await manifest.json();
      var origin = self.location.origin;
      for (var request of await contentCache.keys()) {
        var key = request.url.substring(origin.length + 1);
        if (key == "") {
          key = "/";
        }
        // If a resource from the old manifest is not in the new cache, or if
        // the MD5 sum has changed, delete it. Otherwise the resource is left
        // in the cache and can be reused by the new service worker.
        if (!RESOURCES[key] || RESOURCES[key] != oldManifest[key]) {
          await contentCache.delete(request);
        }
      }
      // Populate the cache with the app shell TEMP files, potentially overwriting
      // cache files preserved above.
      for (var request of await tempCache.keys()) {
        var response = await tempCache.match(request);
        await contentCache.put(request, response);
      }
      await caches.delete(TEMP);
      // Save the manifest to make future upgrades efficient.
      await manifestCache.put('manifest', new Response(JSON.stringify(RESOURCES)));
      // Claim client to enable caching on first launch
      self.clients.claim();
      return;
    } catch (err) {
      // On an unhandled exception the state of the cache cannot be guaranteed.
      console.error('Failed to upgrade service worker: ' + err);
      await caches.delete(CACHE_NAME);
      await caches.delete(TEMP);
      await caches.delete(MANIFEST);
    }
  }());
});
// The fetch handler redirects requests for RESOURCE files to the service
// worker cache.
self.addEventListener("fetch", (event) => {
  if (event.request.method !== 'GET') {
    return;
  }
  var origin = self.location.origin;
  var key = event.request.url.substring(origin.length + 1);
  // Redirect URLs to the index.html
  if (key.indexOf('?v=') != -1) {
    key = key.split('?v=')[0];
  }
  if (event.request.url == origin || event.request.url.startsWith(origin + '/#') || key == '') {
    key = '/';
  }
  // If the URL is not the RESOURCE list then return to signal that the
  // browser should take over.
  if (!RESOURCES[key]) {
    return;
  }
  // If the URL is the index.html, perform an online-first request.
  if (key == '/') {
    return onlineFirst(event);
  }
  event.respondWith(caches.open(CACHE_NAME)
    .then((cache) =>  {
      return cache.match(event.request).then((response) => {
        // Either respond with the cached resource, or perform a fetch and
        // lazily populate the cache only if the resource was successfully fetched.
        return response || fetch(event.request).then((response) => {
          if (response && Boolean(response.ok)) {
            cache.put(event.request, response.clone());
          }
          return response;
        });
      })
    })
  );
});
self.addEventListener('message', (event) => {
  // SkipWaiting can be used to immediately activate a waiting service worker.
  // This will also require a page refresh triggered by the main worker.
  if (event.data === 'skipWaiting') {
    self.skipWaiting();
    return;
  }
  if (event.data === 'downloadOffline') {
    downloadOffline();
    return;
  }
});
// Download offline will check the RESOURCES for all files not in the cache
// and populate them.
async function downloadOffline() {
  var resources = [];
  var contentCache = await caches.open(CACHE_NAME);
  var currentContent = {};
  for (var request of await contentCache.keys()) {
    var key = request.url.substring(origin.length + 1);
    if (key == "") {
      key = "/";
    }
    currentContent[key] = true;
  }
  for (var resourceKey of Object.keys(RESOURCES)) {
    if (!currentContent[resourceKey]) {
      resources.push(resourceKey);
    }
  }
  return contentCache.addAll(resources);
}
// Attempt to download the resource online before falling back to
// the offline cache.
function onlineFirst(event) {
  return event.respondWith(
    fetch(event.request).then((response) => {
      return caches.open(CACHE_NAME).then((cache) => {
        cache.put(event.request, response.clone());
        return response;
      });
    }).catch((error) => {
      return caches.open(CACHE_NAME).then((cache) => {
        return cache.match(event.request).then((response) => {
          if (response != null) {
            return response;
          }
          throw error;
        });
      });
    })
  );
}
