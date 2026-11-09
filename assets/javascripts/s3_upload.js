/*
 * Redmine Serverless S3: uploads attachments from the browser through
 * Redmine's CloudFront distribution to S3 (docs/attachments.md#upload).
 *
 * Replaces uploadBlob of Redmine's attachments.js. The file is hashed with
 * SHA-256 in pieces (Web Crypto needs the whole file in memory), then
 *   1. POST /s3_uploads/presign  -> a CloudFront signed URL and a ticket
 *   2. PUT the file to the URL with x-amz-checksum-sha256; S3 checks it
 *   3. POST /s3_uploads/complete -> the same script as POST /uploads.js;
 *      202 while GuardDuty's malware scan has not finished, then again
 * The progress bar shows hashing as the first half and the PUT as the second.
 */
(function() {
  'use strict';

  var CHUNK_SIZE = 4 * 1024 * 1024;

  // SHA-256 (FIPS 180-4), fed in pieces.
  var K = new Uint32Array([
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
  ]);

  function Sha256() {
    this.h = new Uint32Array([
      0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
    ]);
    this.w = new Uint32Array(64);
    this.buffer = new Uint8Array(64);
    this.buffered = 0;
    this.length = 0;
  }

  Sha256.prototype.block = function(bytes, offset) {
    var w = this.w, h = this.h, i, t1, t2;
    for (i = 0; i < 16; i++, offset += 4) {
      w[i] = (bytes[offset] << 24) | (bytes[offset + 1] << 16) | (bytes[offset + 2] << 8) | bytes[offset + 3];
    }
    for (i = 16; i < 64; i++) {
      var x = w[i - 15], y = w[i - 2];
      var s0 = ((x >>> 7) | (x << 25)) ^ ((x >>> 18) | (x << 14)) ^ (x >>> 3);
      var s1 = ((y >>> 17) | (y << 15)) ^ ((y >>> 19) | (y << 13)) ^ (y >>> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) | 0;
    }
    var a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7];
    for (i = 0; i < 64; i++) {
      t1 = (hh + (((e >>> 6) | (e << 26)) ^ ((e >>> 11) | (e << 21)) ^ ((e >>> 25) | (e << 7))) +
            ((e & f) ^ (~e & g)) + K[i] + w[i]) | 0;
      t2 = ((((a >>> 2) | (a << 30)) ^ ((a >>> 13) | (a << 19)) ^ ((a >>> 22) | (a << 10))) +
            ((a & b) ^ (a & c) ^ (b & c))) | 0;
      hh = g; g = f; f = e; e = (d + t1) | 0; d = c; c = b; b = a; a = (t1 + t2) | 0;
    }
    h[0] += a; h[1] += b; h[2] += c; h[3] += d; h[4] += e; h[5] += f; h[6] += g; h[7] += hh;
  };

  Sha256.prototype.update = function(bytes) {
    var offset = 0, n = bytes.length;
    this.length += n;
    if (this.buffered > 0) {
      var take = Math.min(64 - this.buffered, n);
      this.buffer.set(bytes.subarray(0, take), this.buffered);
      this.buffered += take;
      offset = take;
      if (this.buffered < 64) { return this; }
      this.block(this.buffer, 0);
      this.buffered = 0;
    }
    for (; offset + 64 <= n; offset += 64) { this.block(bytes, offset); }
    if (offset < n) {
      this.buffer.set(bytes.subarray(offset), 0);
      this.buffered = n - offset;
    }
    return this;
  };

  // Returns the digest as 32 bytes.
  Sha256.prototype.digest = function() {
    var bits = this.length * 8;
    var padding = new Uint8Array((this.buffered < 56 ? 56 : 120) - this.buffered + 8);
    padding[0] = 0x80;
    var high = Math.floor(bits / 0x100000000), low = bits >>> 0, end = padding.length;
    padding[end - 8] = high >>> 24; padding[end - 7] = high >>> 16; padding[end - 6] = high >>> 8; padding[end - 5] = high;
    padding[end - 4] = low >>> 24; padding[end - 3] = low >>> 16; padding[end - 2] = low >>> 8; padding[end - 1] = low;
    var length = this.length;
    this.update(padding);
    this.length = length;
    var out = new Uint8Array(32);
    for (var i = 0; i < 8; i++) {
      out[i * 4] = this.h[i] >>> 24; out[i * 4 + 1] = this.h[i] >>> 16;
      out[i * 4 + 2] = this.h[i] >>> 8; out[i * 4 + 3] = this.h[i];
    }
    return out;
  };

  function base64(bytes) {
    var binary = '';
    for (var i = 0; i < bytes.length; i++) { binary += String.fromCharCode(bytes[i]); }
    return window.btoa(binary);
  }

  function readSlice(blob, start, end) {
    var slice = blob.slice(start, end);
    if (slice.arrayBuffer) { return slice.arrayBuffer(); }
    return new Promise(function(resolve, reject) {
      var reader = new FileReader();
      reader.onload = function() { resolve(reader.result); };
      reader.onerror = function() { reject(reader.error); };
      reader.readAsArrayBuffer(slice);
    });
  }

  // Resolves to the base64 SHA-256 of the blob; onProgress(bytes hashed).
  function hashBlob(blob, onProgress) {
    var sha = new Sha256();
    function step(start) {
      if (start >= blob.size) { return Promise.resolve(base64(sha.digest())); }
      var end = Math.min(start + CHUNK_SIZE, blob.size);
      return readSlice(blob, start, end).then(function(buffer) {
        sha.update(new Uint8Array(buffer));
        onProgress(end);
        return step(end);
      });
    }
    return step(0);
  }

  function meta(name) {
    var element = document.querySelector('meta[name="' + name + '"]');
    return element ? element.getAttribute('content') : null;
  }

  function errorText(xhr, fallback) {
    var json = xhr && xhr.responseJSON;
    if (!json && xhr && xhr.responseText) {
      try { json = JSON.parse(xhr.responseText); } catch (e) { json = null; }
    }
    if (json && json.errors && json.errors.length) { return json.errors.join(', '); }
    return (xhr && xhr.statusText && xhr.statusText !== 'error') ? xhr.statusText : fallback;
  }

  function put(url, headers, blob, onLoadstart, onProgress) {
    return new Promise(function(resolve, reject) {
      var xhr = new XMLHttpRequest();
      xhr.open('PUT', url);
      Object.keys(headers).forEach(function(name) { xhr.setRequestHeader(name, headers[name]); });
      xhr.upload.onloadstart = onLoadstart;
      xhr.upload.onprogress = onProgress;
      xhr.onload = function() {
        if (xhr.status >= 200 && xhr.status < 300) { resolve(); } else { reject(xhr); }
      };
      xhr.onerror = function() { reject(xhr); };
      xhr.send(blob);
    });
  }

  // POST /s3_uploads/complete, again while the malware scan answers 202
  // (each request already waits on the server), then runs the script that
  // Redmine's POST /uploads.js would return.
  var COMPLETE_RETRY_DELAYS = [1000, 2000, 4000, 8000, 15000, 30000];

  function complete(url, ticket, attempt) {
    return new Promise(function(resolve, reject) {
      $.ajax(url, { type: 'POST', dataType: 'text', data: { ticket: ticket } })
        .done(function(text, status, xhr) {
          if (xhr.status !== 202) {
            $.globalEval(text);
            resolve(text);
          } else if (attempt < COMPLETE_RETRY_DELAYS.length) {
            setTimeout(function() {
              complete(url, ticket, attempt + 1).then(resolve, reject);
            }, COMPLETE_RETRY_DELAYS[attempt]);
          } else {
            reject('The file is still being scanned for malware. Try again later.');
          }
        })
        .fail(function(xhr) { reject(errorText(xhr, 'Upload failed')); });
    });
  }

  var originalUploadBlob = null;

  function s3UploadBlob(blob, uploadUrl, attachmentId, options) {
    var presignUrl = meta('redmine-s3-presign-url'), completeUrl = meta('redmine-s3-complete-url');
    if (!presignUrl || !completeUrl || !window.Promise || !window.Uint8Array || !blob || !blob.slice) {
      return originalUploadBlob.apply(this, arguments);
    }
    var actualOptions = $.extend({ loadstartEventHandler: $.noop, progressEventHandler: $.noop }, options);
    var deferred = $.Deferred();
    var size = blob.size, total = Math.max(size, 1) * 2;
    var filename = blob.name || ('upload-' + Math.random().toString(16).slice(2));
    var progress = function(loaded) {
      actualOptions.progressEventHandler({ lengthComputable: true, loaded: loaded, total: total });
    };
    var fail = function(text) { deferred.reject({ statusText: text }); };

    actualOptions.loadstartEventHandler({});
    hashBlob(blob, progress).then(function(sha256) {
      $.ajax(presignUrl, {
        type: 'POST', dataType: 'json',
        data: { filename: filename, size: size, sha256: sha256, content_type: blob.type || '' }
      }).done(function(presigned) {
        put(presigned.url, presigned.headers, blob, $.noop, function(e) {
          if (e.lengthComputable) { progress(size + e.loaded * size / Math.max(e.total, 1)); }
        }).then(function() {
          complete(completeUrl + '?attachment_id=' + encodeURIComponent(attachmentId), presigned.ticket, 0)
            .then(function(script) { deferred.resolve(script); }, function(text) { fail(text); });
        }, function(xhr) {
          fail(errorText(xhr, 'Upload failed (' + (xhr.status || 'network error') + ')'));
        });
      }).fail(function(xhr) { fail(errorText(xhr, 'Upload failed')); });
    }, function(error) {
      fail(String(error && error.message || error || 'Could not read the file'));
    });
    return deferred.promise();
  }

  // attachments.js defines uploadBlob as a global function and can be loaded
  // again with forms that come through Ajax, so the replacement is put back
  // before each user action that adds files.
  function install() {
    if (typeof window.uploadBlob === 'function' && window.uploadBlob !== s3UploadBlob) {
      originalUploadBlob = window.uploadBlob;
      window.uploadBlob = s3UploadBlob;
    }
  }

  window.RedmineS3Upload = {
    Sha256: Sha256, base64: base64, hashBlob: hashBlob, complete: complete, uploadBlob: s3UploadBlob,
    retryDelays: COMPLETE_RETRY_DELAYS
  };
  document.addEventListener('DOMContentLoaded', install);
  ['change', 'drop', 'paste'].forEach(function(type) { document.addEventListener(type, install, true); });
})();
