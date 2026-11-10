// The options page: whether the helper app is connected, the locked group's title, and a way to the
// shortcuts page, which a web page cannot link to. Safari has neither tab groups nor a shortcuts page
// an extension can open, so there both are hidden.
const group = document.getElementById('group');
if (!chrome.tabGroups) document.getElementById('groups').hidden = true;
if (!chrome.runtime.getURL('').startsWith('chrome-extension:')) document.getElementById('shortcuts').hidden = true;

chrome.runtime.sendMessage({ status: true }).then(({ helper, lockedGroup }) => {
  document.getElementById('dot').classList.toggle('on', helper);
  document.getElementById('helper').textContent = helper ? 'Monochrome app connected' : 'Monochrome app not connected';
  group.value = lockedGroup;
});

group.addEventListener('change', () => chrome.storage.local.set({ lockedGroup: group.value.trim() || 'CoreCore' }));
document.getElementById('shortcuts').onclick = () => chrome.tabs.create({ url: 'chrome://extensions/shortcuts' });
