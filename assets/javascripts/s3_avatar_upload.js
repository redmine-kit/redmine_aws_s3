/*
 * Redmine AWS S3: the avatar form of Redmine 7.1 (/my/avatar and
 * /users/:id/avatar) sends the image through Redmine's CloudFront
 * distribution to S3 (docs/attachments.md#avatars).
 *
 * Why a script: the form sends the image in its body, and a request through
 * CloudFront to Redmine on Lambda carries at most 1 MB, less than a photo
 * from a phone. Only the browser can send the image to S3 with a signed PUT
 * before the form is submitted.
 *
 * Works with Redmine's avatar form (app/views/avatars/, no script of its
 * own), rails-ujs, which disables its submit button, and s3_upload.js, whose
 * PUT and error handling it uses. When the form is submitted with a file:
 *   1. POST /s3_uploads/avatar/presign -> a CloudFront signed URL and a ticket
 *   2. PUT the image to the URL
 *   3. POST /s3_uploads/avatar/check   -> 202 while GuardDuty's malware scan
 *      has not finished, then again
 *   4. Submit Redmine's form with the ticket in place of the file; Redmine
 *      registers the avatar as it does a file sent in the form.
 * Without this script (or s3_upload.js, which it uses), the form sends the
 * file to Redmine as usual.
 */
(function() {
  'use strict';

  var CHECK_RETRY_DELAYS = [1000, 2000, 4000, 8000, 15000, 30000];

  function meta(name) {
    var element = document.querySelector('meta[name="' + name + '"]');
    return element ? element.getAttribute('content') : null;
  }

  function post(url, data) {
    return new Promise(function(resolve, reject) {
      $.ajax(url, { type: 'POST', dataType: 'json', data: data })
        .done(function(json, status, xhr) { resolve({ json: json, status: xhr.status }); })
        .fail(function(xhr) { reject(window.RedmineS3Upload.errorText(xhr, 'Upload failed')); });
    });
  }

  function wait(milliseconds) {
    return new Promise(function(resolve) { setTimeout(resolve, milliseconds); });
  }

  // Resolves when the upload can be registered.
  function check(url, ticket, attempt) {
    return post(url, { ticket: ticket }).then(function(result) {
      if (result.status !== 202) { return null; }
      if (attempt >= CHECK_RETRY_DELAYS.length) {
        throw 'The file is still being scanned for malware. Try again later.';
      }
      return wait(CHECK_RETRY_DELAYS[attempt]).then(function() { return check(url, ticket, attempt + 1); });
    });
  }

  // The same markup as Redmine's error_messages_for, above the form's box.
  function showError(form, text) {
    var box = document.getElementById('errorExplanation');
    if (!box) {
      box = document.createElement('div');
      box.id = 'errorExplanation';
      var anchor = form.closest('.box') || form;
      anchor.parentNode.insertBefore(box, anchor);
    }
    var list = document.createElement('ul');
    var item = document.createElement('li');
    item.textContent = text;
    list.appendChild(item);
    box.replaceChildren(list);
  }

  // rails-ujs disables the submit button on submit; it is enabled again
  // when the upload fails. rails-ujs disables it 13 ms after the submit
  // event, so an error answered sooner (a refused size) is followed by a
  // second enabling after that.
  var ENABLE_AGAIN_AFTER = 50;

  function enable(form) {
    var run = function() {
      if (window.Rails && typeof window.Rails.enableElement === 'function') { window.Rails.enableElement(form); }
      form.querySelectorAll('input[type="submit"]').forEach(function(button) { button.disabled = false; });
    };
    run();
    setTimeout(run, ENABLE_AGAIN_AFTER);
  }

  function upload(form, input, file) {
    var presignUrl = meta('redmine-s3-avatar-presign-url'), checkUrl = meta('redmine-s3-avatar-check-url');
    return post(presignUrl, { filename: file.name, size: file.size, content_type: file.type || '' })
      .then(function(result) {
        var presigned = result.json;
        $('#ajax-indicator').show();
        return window.RedmineS3Upload.put(presigned.url, file, $.noop).then(function() {
          return presigned.ticket;
        }, function(xhr) {
          throw window.RedmineS3Upload.errorText(xhr, 'Upload failed (' + (xhr.status || 'network error') + ')');
        });
      })
      .then(function(ticket) {
        return check(checkUrl, ticket, 0).then(function() { return ticket; });
      })
      .then(function(ticket) {
        var field = document.createElement('input');
        field.type = 'hidden';
        field.name = 's3_ticket';
        field.value = ticket;
        form.appendChild(field);
        // A disabled field is not sent: the form carries the ticket only.
        input.disabled = true;
        form.submit();
      });
  }

  function onSubmit(event) {
    var form = event.currentTarget;
    var input = form.querySelector('input[type="file"][name="avatar"]');
    var file = input && input.files && input.files[0];
    if (!file || !window.Promise || !window.RedmineS3Upload || !meta('redmine-s3-avatar-presign-url')) { return; }

    event.preventDefault();
    upload(form, input, file).catch(function(text) {
      $('#ajax-indicator').hide();
      showError(form, String(text));
      enable(form);
    });
  }

  function install() {
    var input = document.querySelector('form input[type="file"][name="avatar"]');
    if (input && input.form) { input.form.addEventListener('submit', onSubmit); }
  }

  // Coming back to the page from the browser's history: the file field
  // again, without the ticket.
  window.addEventListener('pageshow', function() {
    document.querySelectorAll('input[name="s3_ticket"]').forEach(function(field) { field.remove(); });
    var input = document.querySelector('form input[type="file"][name="avatar"]');
    if (input) { input.disabled = false; }
  });

  window.RedmineS3AvatarUpload = { check: check, retryDelays: CHECK_RETRY_DELAYS, enable: enable };
  document.addEventListener('DOMContentLoaded', install);
})();
