export function normalizeUrl(input: string) {
  const trimmed = input.trim();
  return trimmed.endsWith("/") ? trimmed.slice(0, -1) : trimmed;
}

export function getSourceSearchCandidates(input: string): string[] {
  try {
    const url = new URL(input);
    // 包含完整协议，确保精确匹配
    const base = `${url.protocol}//${url.host}${url.pathname}${url.search}`;
    const trimmed = base.endsWith("/") ? base.slice(0, -1) : base;

    // 返回带协议和不带协议的版本，以兼容不同的存储方式
    const candidates = [base];
    if (trimmed !== base) {
      candidates.push(trimmed);
    }

    // 也要包含不带协议的版本以兼容旧数据
    const withoutProtocol = `${url.host}${url.pathname}${url.search}`;
    const withoutProtocolTrimmed = withoutProtocol.endsWith("/") ? withoutProtocol.slice(0, -1) : withoutProtocol;
    if (!candidates.includes(withoutProtocol)) {
      candidates.push(withoutProtocol);
    }
    if (!candidates.includes(withoutProtocolTrimmed) && withoutProtocolTrimmed !== withoutProtocol) {
      candidates.push(withoutProtocolTrimmed);
    }

    return candidates;
  } catch {
    return [];
  }
}

