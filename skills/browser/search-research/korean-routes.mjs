// @ts-check

const NAVER_PATTERN = /네이버|naver|블로그|카페|지식인/i;
const NAMUWIKI_PATTERN = /나무위키|namu\.wiki|namuwiki/i;
const OFFICIAL_PATTERN = /공식|기관|정부|공지사항|보도자료|통합누리집|지원금|보조금|정책|go\.kr|or\.kr/i;
const BOOKSTORE_PATTERN = /교보문고|yes24|알라딘|출판|도서|책|isbn|목차|쪽수|페이지/i;
const ACADEMIC_PATTERN = /논문|학술|대학교|대학원|DBpia|KCI|RISS|arXiv|학회/i;
const STRUCTURED_PATTERN = /표|목록|순위|랭킹|n번째|번째|상위|하위|항목|리스트/i;
const DATE_PATTERN = /\b20\d{2}\b|20\d{2}년|\d{1,2}월|\d{1,2}일|최신|현재|오늘|어제|이번|지난/i;

/**
 * @param {string} text
 */
export function detectSourceHints(text = '') {
    const sourceHints = [];
    if (NAVER_PATTERN.test(text)) sourceHints.push('naver');
    if (NAMUWIKI_PATTERN.test(text)) sourceHints.push('namuwiki');
    if (OFFICIAL_PATTERN.test(text)) sourceHints.push('official');
    if (BOOKSTORE_PATTERN.test(text)) sourceHints.push('bookstore');
    if (ACADEMIC_PATTERN.test(text)) sourceHints.push('academic');
    if (STRUCTURED_PATTERN.test(text)) sourceHints.push('structured');
    if (DATE_PATTERN.test(text)) sourceHints.push('date');
    return [...new Set(sourceHints)];
}

/**
 * @param {string} query
 * @param {string[]} [sourceHints]
 */
export function chooseKoreanRoute(query = '', sourceHints = detectSourceHints(query)) {
    const hints = new Set(sourceHints);
    if (hints.has('naver')) return 'naver_search';
    if (hints.has('namuwiki')) return 'namuwiki';
    if (hints.has('bookstore')) return 'bookstore';
    if (hints.has('academic')) return 'academic';
    if (hints.has('official')) return 'official_site';
    return 'google_kr';
}

/**
 * @param {string} route
 * @param {string} query
 */
export function buildRouteUrl(route, query) {
    const encoded = encodeURIComponent(query);
    if (route === 'naver_search') return `https://search.naver.com/search.naver?query=${encoded}`;
    if (route === 'namuwiki') return `https://namu.wiki/Search?q=${encoded}`;
    if (route === 'bookstore') return `https://search.kyobobook.co.kr/search?keyword=${encoded}`;
    if (route === 'academic') return `https://scholar.google.com/scholar?hl=ko&q=${encoded}`;
    return `https://www.google.com/search?hl=ko&gl=kr&q=${encoded}`;
}

/**
 * @param {string} text
 */
export function needsBrowseEscalation(text = '') {
    const hints = detectSourceHints(text);
    return hints.includes('naver')
        || hints.includes('structured')
        || /iframe|PostView|자바스크립트|javascript|동적|탭|필터|페이지네이션|무한스크롤/i.test(text);
}
