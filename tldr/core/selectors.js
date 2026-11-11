// Selectors for blocks the reader leaves out, by label. These are generic class and id patterns written
// for this project, not taken from a filter list: EasyList's licence is an open decision (docs/tldr.md,
// open decision 6). A .js file, not JSON, because the worker injects scripts only and the manifest has
// no web_accessible_resources. Short words are matched as whole class names or with their hyphen, since
// "toc" is in "protocol" and "ad" is in "header".
(() => {
  const T = globalThis.__tldr ??= {};
  T.selectors = {
    generic: {
      ad: [
        '.ad', '.ads', '.advert', '.advertisement', '.adsbygoogle', '.ad-slot', '.ad-unit', '.ad-container', '.ad-wrapper',
        '[class^="ad-"]', '[class*=" ad-"]', '[class$="-ad"]', '[class*="-ad "]', '[class*="_ad_"]', '[class*="advert"]',
        '[id^="ad-"]', '[id$="-ad"]', '[id*="advert"]', '[id^="google_ads"]', '[id^="div-gpt-ad"]',
        '[data-ad]', '[data-ad-slot]', '[data-ad-unit]', '[data-google-query-id]', '[aria-label="Advertisement" i]',
        '[class*="outbrain"]', '[class*="taboola"]', '[id*="taboola"]', '[id*="outbrain"]',
      ],
      sponsored: ['[class*="sponsor"]', '[id*="sponsor"]', '[class*="partner-content"]', '[class*="paid-content"]', '[class*="native-ad"]'],
      promo: [
        '.promo', '[class*="promo-"]', '[class*="-promo"]', '[class*="newsletter"]', '[id*="newsletter"]', '[class*="subscribe"]',
        '[class*="signup"]', '[class*="sign-up"]', '.related', '[class*="related-"]', '[class*="-related"]', '[id^="related"]',
        '[class*="recommended"]', '[class*="more-from"]', '[class*="read-more"]', '[class*="read-next"]', '[class*="most-read"]',
        '[class*="most-popular"]', '[class*="trending"]', '[class*="paywall"]', '[class*="donate"]', '.cta', '[class*="call-to-action"]',
      ],
      navigation: [
        '[class*="breadcrumb"]', '.sidebar', '[class*="sidebar-"]', '[class*="-sidebar"]', '#sidebar', '[class*="site-header"]',
        '[class*="site-footer"]', '[class*="navbar"]', '.menu', '[class*="nav-menu"]', '[class*="pagination"]', '.pager',
        '[class*="skip-link"]', '.toc', '#toc', '[class*="table-of-contents"]', '.tags', '.tag-list',
      ],
      other: [
        '.share', '[class*="share-"]', '[class*="-share"]', '[class*="sharing"]', '.social', '[class*="social-"]', '[class*="-social"]',
        '[class*="cookie"]', '[class*="consent"]', '[class*="gdpr"]', '[class*="popup"]', '.modal', '[class*="modal-"]',
        '.comments', '#comments', '[class*="comment-"]', '[class*="comments-"]', '#disqus_thread', '.noprint',
        '.screen-reader-text', '.visually-hidden', '.sr-only',
      ],
    },
    // By host: the page's host is this name or ends with a dot and this name.
    hosts: {
      'wikipedia.org': {
        navigation: ['.mw-editsection', '.navbox', '.navbox-styles', '.sistersitebox', '.side-box', '.vector-toc', '.mw-jump-link', '.catlinks', '.printfooter', '.portalbox', '.authority-control'],
        other: ['.ambox', '.metadata', '.mw-empty-elt', '.shortdescription', '.hatnote', '.noexcerpt'],
      },
    },
  };
})();
