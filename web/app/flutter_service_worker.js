'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {"flutter_bootstrap.js": "02a6bc82799643dafa4fb76000db51f3",
".vercel/project.json": "750c0a5654772be390e5bc69a32abba8",
".vercel/README.txt": "2b13c79d37d6ed82a3255b83b6815034",
"version.json": "010dae4751173c409ea9953421a520b8",
"index.html": "a0f5ef6d065b9ad82d5742846fc6ac7f",
"/": "a0f5ef6d065b9ad82d5742846fc6ac7f",
"vercel.json": "bbc1b25f44c75a2d8895ac6711baed70",
"firebase-messaging-sw.js": "406c31f9d237c56c8c1fc8ceb75b6b5d",
"support.html": "a9a4b6f8216bfba4a17db941cc37bdd9",
"main.dart.js": "e26063ebf118c3c0d02b7a4703c95517",
"flutter.js": "24bc71911b75b5f8135c949e27a2984e",
"favicon.png": "db652681fa5504c0a0027bbf8a3a2329",
"icons/Icon-192.png": "db652681fa5504c0a0027bbf8a3a2329",
"icons/Icon-maskable-192.png": "db652681fa5504c0a0027bbf8a3a2329",
"icons/Icon-maskable-512.png": "56814cfb51ad91c2895c3c777143dffa",
"icons/Icon-512.png": "56814cfb51ad91c2895c3c777143dffa",
"manifest.json": "a3999474f59d1e90056a189cffef9495",
"build/ios/XCBuildData/PIFCache/target/TARGET@v11_hash=5b830d8f0f7344e46349392123f22d65-json": "8cfda9619d514db9744dd6aabfdc4274",
"build/ios/XCBuildData/PIFCache/target/TARGET@v11_hash=ac13f9d62a763f51e3692e207f246bc0-json": "a0f77d8c9cae218fbb7437e01ecb1a96",
"build/ios/XCBuildData/PIFCache/target/TARGET@v11_hash=c0ef9b47223b40067bb967dc7795394e-json": "2e9f28ecccf0360d955e456fb89f3d2d",
"build/ios/XCBuildData/PIFCache/target/TARGET@v11_hash=ff33f42d0017f3ae162e1c0de9f40c3c-json": "f07561f3c4b40ace932e56041c4472fb",
"build/ios/XCBuildData/PIFCache/target/TARGET@v11_hash=9b4d0086944b0e929ca85df3b46fe4c5-json": "95dea93ee14c9cbf127b89adc8d5031d",
"build/ios/XCBuildData/PIFCache/target/TARGET@v11_hash=1c459a83ce4a01ce2c560feedb232625-json": "a797c750b8ca7975ae6d62dbb2863f8e",
"build/ios/XCBuildData/PIFCache/target/TARGET@v11_hash=52b8020b8084500a11084029483807d2-json": "c7d985c5dbcc4bf84d26ca6256fa33d0",
"build/ios/XCBuildData/PIFCache/target/TARGET@v11_hash=865f02981824d4a37f55de2c5eebad2d-json": "ed8075a9bf4d6339813a89203af8ff94",
"build/ios/XCBuildData/PIFCache/target/TARGET@v11_hash=4ba2e1f17014e1f601bdf3b35aad79c0-json": "baf78c7fd4092e052c85aca1840ea348",
"build/ios/XCBuildData/PIFCache/target/TARGET@v11_hash=76d89300b9728ed5a23b2ffb770bf4f9-json": "7f47d046515193c5479644319d8494ac",
"build/ios/XCBuildData/PIFCache/target/TARGET@v11_hash=618b5d3b1971bcb2426bc8834095bfa3-json": "4e186385eae66df00304711d60d2c137",
"build/ios/XCBuildData/PIFCache/target/TARGET@v11_hash=dd69010d6730fe848c6ff1f144eb19ca-json": "479219c5f34cf2197b6854106a2c6d0a",
"build/ios/XCBuildData/PIFCache/target/TARGET@v11_hash=f4691881017590a09c7209c4e3d8e3fd-json": "1e51ba5c1a376f23607692a8a6467bef",
"build/ios/XCBuildData/PIFCache/target/TARGET@v11_hash=94db24eaf69d4cc91cfd07889a455bfc-json": "a0a7a1e86ae92e2e6ae00493a0d43782",
"build/ios/XCBuildData/PIFCache/target/TARGET@v11_hash=b69e492ebee0eb4ce92e3069b6fea703-json": "c89b7d54053e83aa8fbe9fe8022544ea",
"build/ios/XCBuildData/PIFCache/target/TARGET@v11_hash=05f26ea550211e81afb381f4479fba37-json": "8ba72ca0682aa423d88a230fbb2650a5",
"build/ios/XCBuildData/PIFCache/target/TARGET@v11_hash=abb0dfc64fc1be52b15412388779918b-json": "eb822e6d7d825adbc1c18fa316c3101c",
"build/ios/XCBuildData/PIFCache/target/TARGET@v11_hash=fdc29f586e15ce29e972a3d6879d7971-json": "2d54c8ce30d1c0f5e7c60d3b81374c27",
"build/ios/XCBuildData/PIFCache/target/TARGET@v11_hash=e5a451f7b9d425a3ae558ea38ec6c958-json": "c704343fb7725fafef0ac221e8b8785d",
"build/ios/XCBuildData/PIFCache/target/TARGET@v11_hash=134175e5e7d0d7115c30d8b636fbc7d1-json": "ca4f52b48cfcfbf544bb5cdfbdd93f37",
"build/ios/XCBuildData/PIFCache/target/TARGET@v11_hash=ab2cf6a5bfb9a60acffc7b58ca9c277f-json": "da83442d4819dcdeaf0158a037903e7e",
"build/ios/XCBuildData/PIFCache/target/TARGET@v11_hash=0b57224bd8dd52e0ca94339bcf1c788d-json": "acbae03c7dfb8c2255015e530fc06865",
"build/ios/XCBuildData/PIFCache/target/TARGET@v11_hash=203b87c3954f6a95e1b7c7c753adf9e6-json": "7aee8bf2fa2ce8b921a3b75757bbc335",
"build/ios/XCBuildData/PIFCache/target/TARGET@v11_hash=ba96985579edfc1c9725691bff97f16b-json": "e8e5eb3f833124171a2b12f1391df815",
"build/ios/XCBuildData/PIFCache/target/TARGET@v11_hash=8ca50d025f3855454bfacdceafc6daa6-json": "c160bb9c84319dcc3324c532e7ca3b8d",
"build/ios/XCBuildData/PIFCache/target/TARGET@v11_hash=ebd28b37a34113534b84f0224ecb7a9a-json": "8ea1ab11634f3b5cf3f0a904e82b3d26",
"build/ios/XCBuildData/PIFCache/target/TARGET@v11_hash=0d5f235e591b789176a2bdc0f7ad1e82-json": "55af4c675c8842e4e35176c5fa926b67",
"build/ios/XCBuildData/PIFCache/target/TARGET@v11_hash=c0b382edf050a412b2fcfa9526a4ad63-json": "a0cc072a26913f035aa92ffce001e908",
"build/ios/XCBuildData/PIFCache/target/TARGET@v11_hash=9ea6b9df3cb62b1f089f7c994f4a5197-json": "0a3a702ca144d4f11739731de665fc68",
"build/ios/XCBuildData/PIFCache/target/TARGET@v11_hash=695c3ddb67543c02e3c75de821509bbc-json": "0256a8f6319af7c19a4bce7a82f8015a",
"build/ios/XCBuildData/PIFCache/target/TARGET@v11_hash=d8355931a4530bf07081eac8e098d980-json": "f8f993700fd4c5611c4f686913ba4d41",
"build/ios/XCBuildData/PIFCache/target/TARGET@v11_hash=69da16d890667b00099ebf8542f630d1-json": "e523db04b0ded3638f4f2448dd9d45b5",
"build/ios/XCBuildData/PIFCache/target/TARGET@v11_hash=cdd5e3e4424a53eb618db42b8b589b1f-json": "0d04e800549273d585ee65de2333e466",
"build/ios/XCBuildData/PIFCache/target/TARGET@v11_hash=ad3a33df302ab9013ea470de998e7be0-json": "99b09067b340645010cab82753d9ee5d",
"build/ios/XCBuildData/PIFCache/target/TARGET@v11_hash=53b63c7889e79d7da03389bb2e56418e-json": "357f3015e5cbd562e51e0421ba0649ee",
"build/ios/XCBuildData/PIFCache/target/TARGET@v11_hash=a9bbac0f1f9ad0424578b3b073c15c17-json": "cc7aa5d1b37b03cf5a871024291c07a0",
"build/ios/XCBuildData/PIFCache/target/TARGET@v11_hash=96ce9a20f44c59390ac3b4cd06381fd5-json": "e0e8ff0bf763eb87ef149ec325e4b83d",
"build/ios/XCBuildData/PIFCache/target/TARGET@v11_hash=1521a068002480472161be1a3db7b7a3-json": "5bc95215fe651c874c3a2347fdce8def",
"build/ios/XCBuildData/PIFCache/target/TARGET@v11_hash=4dc1b3c39e75bcd8e9cbc67ca90c4ad7-json": "b0e9cc6e32b89b47dec57049e735c0b2",
"build/ios/XCBuildData/PIFCache/target/TARGET@v11_hash=acff477ef5a2f700a741417a508452e7-json": "9715575ff807474752ec75154812f6b2",
"build/ios/XCBuildData/PIFCache/target/TARGET@v11_hash=98340a25a40770facb343945917227f7-json": "8b57fb8bc257af8cc3fd1cdc97ae7cdb",
"build/ios/XCBuildData/PIFCache/target/TARGET@v11_hash=566a7ed06e3fb47dc46669486d2e4e25-json": "e5edcd976547a944049198086d56ee4b",
"build/ios/XCBuildData/PIFCache/workspace/WORKSPACE@v11_hash=(null)_subobjects=6ec424e66e2742626843b96ce5ebf55d-json": "d070fc28f8a47cee6a86b73a8140047c",
"build/ios/XCBuildData/PIFCache/project/PROJECT@v11_mod=3c8f0efacde7f3d07dc3b18d683b5f78_hash=bfdfe7dc352907fc980b868725387e98plugins=1OJSG6M1FOV3XYQCBH7Z29RZ0FPR9XDE1-json": "5e5e6bb38f73484f4907b9e7568de1ec",
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
