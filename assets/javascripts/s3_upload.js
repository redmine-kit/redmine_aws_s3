/*
 * Redmine AWS S3: uploads attachments from the browser through
 * Redmine's CloudFront distribution to S3 (docs/attachments.md#upload).
 *
 * Why a script: Redmine's attachments.js sends each file in the body of
 * POST /uploads.js, and a request through CloudFront to Redmine on Lambda
 * carries at most 1 MB. The file has to go from the browser to S3 with a
 * signed PUT, which no markup or server-side code of the plugin can make the
 * browser send.
 *
 * Works with Redmine's attachments.js (app/assets/javascripts/attachments.js):
 * only its uploadBlob is replaced, so that its queue, progress bar, token
 * handling and error display stay Redmine's. When the plugin's <meta> tags
 * are missing, Redmine's own uploadBlob runs.
 *   1. POST /s3_uploads/presign  -> a CloudFront signed URL and a ticket
 *   2. PUT the file to the URL
 *   3. POST /s3_uploads/complete -> the same script as POST /uploads.js;
 *      202 while GuardDuty's malware scan has not finished, then again.
 *      S3 computes the file's SHA-256 when Redmine copies it.
 */
(function() {
  'use strict';

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

  function put(url, blob, onProgress) {
    return new Promise(function(resolve, reject) {
      var xhr = new XMLHttpRequest();
      xhr.open('PUT', url);
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
    if (!presignUrl || !completeUrl || !window.Promise || !blob) {
      return originalUploadBlob.apply(this, arguments);
    }
    var actualOptions = $.extend({ loadstartEventHandler: $.noop, progressEventHandler: $.noop }, options);
    var deferred = $.Deferred();
    var filename = blob.name || ('upload-' + Math.random().toString(16).slice(2));
    var fail = function(text) { deferred.reject({ statusText: text }); };

    actualOptions.loadstartEventHandler({});
    $.ajax(presignUrl, {
      type: 'POST', dataType: 'json',
      data: { filename: filename, size: blob.size, content_type: blob.type || '' }
    }).done(function(presigned) {
      put(presigned.url, blob, actualOptions.progressEventHandler).then(function() {
        complete(completeUrl + '?attachment_id=' + encodeURIComponent(attachmentId), presigned.ticket, 0)
          .then(function(script) { deferred.resolve(script); }, function(text) { fail(text); });
      }, function(xhr) {
        fail(errorText(xhr, 'Upload failed (' + (xhr.status || 'network error') + ')'));
      });
    }).fail(function(xhr) { fail(errorText(xhr, 'Upload failed')); });
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
    complete: complete, uploadBlob: s3UploadBlob, retryDelays: COMPLETE_RETRY_DELAYS, put: put, errorText: errorText
  };
  document.addEventListener('DOMContentLoaded', install);
  ['change', 'drop', 'paste'].forEach(function(type) { document.addEventListener(type, install, true); });
})();
