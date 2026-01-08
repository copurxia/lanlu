export function displayTag(tag: string): string {
  const key = String(tag || '').trim();
  if (!key) return '';
  const idx = key.indexOf(':');
  return idx > 0 ? key.slice(idx + 1) : key;
}

export function getSearchQueryForTag(fullTag: string, tagTranslations: Record<string, string>): string {
  const colonIdx = fullTag.indexOf(':');
  const namespace = colonIdx > 0 ? fullTag.slice(0, colonIdx).trim() : '';
  const translatedText = colonIdx > 0 ? fullTag.slice(colonIdx + 1).trim() : fullTag;

  let originalTag = '';
  let bestMatch = '';

  for (const [origTag, translated] of Object.entries(tagTranslations)) {
    if (translated === translatedText) {
      const origColonIdx = origTag.indexOf(':');
      const origNamespace = origColonIdx > 0 ? origTag.slice(0, origColonIdx).trim() : '';

      if (origNamespace === namespace) {
        originalTag = origTag;
        break;
      } else if (bestMatch === '') {
        bestMatch = origTag;
      }
    }
  }

  if (originalTag === '' && bestMatch !== '') {
    originalTag = bestMatch;
  }

  if (originalTag === '') {
    originalTag = fullTag;
  }

  return originalTag;
}

