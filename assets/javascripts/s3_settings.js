/*
 * Redmine AWS S3: a note next to "Maximum attachment size" on
 * Administration › Settings › Files (docs/admin.md#maximum-attachment-size).
 *
 * Why a script: Redmine's settings/_attachments.html.erb has no hook, and the
 * note belongs next to the field it is about, as the em.info notes of that
 * tab are. It works with that view only (the field
 * #settings_attachment_max_size); the text comes from the plugin's locale,
 * in the <meta> tag that RedmineAws::S3::Hooks adds with this script.
 */
(function() {
  'use strict';

  document.addEventListener('DOMContentLoaded', function() {
    var note = document.querySelector('meta[name="redmine-s3-max-size-note"]');
    var input = document.getElementById('settings_attachment_max_size');
    if (!note || !input || !input.parentNode) { return; }
    var em = document.createElement('em');
    em.className = 'info';
    em.textContent = note.getAttribute('content');
    input.parentNode.appendChild(em);
  });
})();
