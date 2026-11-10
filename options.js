// The options page: whether the app is connected, the locked group's title, and a way to the
// shortcuts page, which a web page cannot link to. The app owns the settings (docs/settings.md): while it
// is connected the title is read-only here and Monochrome Settings… opens its settings window; while it is
// not, the title can be set here, since the extension runs without the app. Safari has neither tab
// groups nor a shortcuts page an extension can open, so there both are hidden.
const group = document.getElementById('group');
const note = document.getElementById('group-note');
const appSettings = document.getElementById('app-settings');
if (!chrome.tabGroups) document.getElementById('groups').hidden = true;
if (!chrome.runtime.getURL('').startsWith('chrome-extension:')) document.getElementById('shortcuts').hidden = true;

chrome.runtime.sendMessage({ status: true }).then(({ helper, lockedGroup }) => {
  document.getElementById('dot').classList.toggle('on', helper);
  document.getElementById('helper').textContent = helper ? 'Monochrome app connected' : 'Monochrome app not connected';
  group.value = lockedGroup;
  group.disabled = helper;
  group.placeholder = 'none';
  if (helper) note.textContent = 'Set in Monochrome\'s settings.';
  appSettings.hidden = !helper;
  document.body.dataset.ready = '1';
});

group.addEventListener('change', () => chrome.runtime.sendMessage({ lockedGroup: group.value }));
appSettings.onclick = () => chrome.runtime.sendMessage({ appSettings: true });
document.getElementById('shortcuts').onclick = () => chrome.tabs.create({ url: 'chrome://extensions/shortcuts' });
