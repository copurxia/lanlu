import React, {useState, useEffect, useCallback} from 'react';
import {
  ActivityIndicator,
  FlatList,
  Modal,
  StyleSheet,
  Text,
  TextInput,
  TouchableOpacity,
  View,
} from 'react-native';

import {addArchiveToTankoubon, searchArchives} from '../../api/lanlu';
import {colors} from '../../theme/colors';
import type {TFunction} from '../../i18n';
import type {Archive} from '../../types/api';

type Props = {
  visible: boolean;
  tankoubonId: string;
  existingArcids: Set<string>;
  onClose: () => void;
  onAdded: () => void;
  t: TFunction;
};

export function AddArchiveDialog({
  visible,
  tankoubonId,
  existingArcids,
  onClose,
  onAdded,
  t,
}: Props) {
  const [query, setQuery] = useState('');
  const [results, setResults] = useState<Archive[]>([]);
  const [loading, setLoading] = useState(false);
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [adding, setAdding] = useState(false);

  useEffect(() => {
    if (!visible) {
      setQuery('');
      setResults([]);
      setSelected(new Set());
    }
  }, [visible]);

  const handleSearch = useCallback(async () => {
    if (!query.trim()) return;
    setLoading(true);
    try {
      const result = await searchArchives({
        filter: query.trim(),
        page: 1,
        pageSize: 30,
        lang: 'en',
      });
      const filtered = result.data
        .filter((item): item is Archive => 'arcid' in item)
        .filter(a => !existingArcids.has(a.arcid));
      setResults(filtered);
    } catch {
      setResults([]);
    } finally {
      setLoading(false);
    }
  }, [query, existingArcids]);

  const toggleSelect = (arcid: string) => {
    setSelected(prev => {
      const next = new Set(prev);
      if (next.has(arcid)) next.delete(arcid);
      else next.add(arcid);
      return next;
    });
  };

  const handleAdd = useCallback(async () => {
    if (selected.size === 0) return;
    setAdding(true);
    try {
      await Promise.all(
        Array.from(selected).map(arcid =>
          addArchiveToTankoubon(tankoubonId, arcid),
        ),
      );
      onAdded();
      onClose();
    } catch {
      // silently fail
    } finally {
      setAdding(false);
    }
  }, [selected, tankoubonId, onAdded, onClose]);

  return (
    <Modal visible={visible} animationType="slide" transparent>
      <View style={styles.overlay}>
        <View style={styles.container}>
          <View style={styles.header}>
            <Text style={styles.title}>{t('tankoubon.addArchive')}</Text>
            <TouchableOpacity onPress={onClose}>
              <Text style={styles.closeText}>{t('common.close')}</Text>
            </TouchableOpacity>
          </View>

          <View style={styles.searchRow}>
            <TextInput
              style={styles.input}
              value={query}
              onChangeText={setQuery}
              placeholder={t('tankoubon.searchArchivesPlaceholder')}
              placeholderTextColor={colors.textMuted}
              onSubmitEditing={handleSearch}
              returnKeyType="search"
            />
            <TouchableOpacity style={styles.searchButton} onPress={handleSearch}>
              <Text style={styles.searchButtonText}>{t('common.search')}</Text>
            </TouchableOpacity>
          </View>

          {loading ? (
            <ActivityIndicator color={colors.primary} style={styles.loading} />
          ) : results.length > 0 ? (
            <FlatList
              data={results}
              keyExtractor={item => item.arcid}
              style={styles.list}
              contentContainerStyle={styles.listContent}
              renderItem={({item}) => {
                const isSelected = selected.has(item.arcid);
                return (
                  <TouchableOpacity
                    style={[styles.resultItem, isSelected && styles.resultItemSelected]}
                    onPress={() => toggleSelect(item.arcid)}>
                    <View style={styles.checkbox}>
                      {isSelected ? (
                        <Text style={styles.checkboxChecked}>✓</Text>
                      ) : null}
                    </View>
                    <View style={styles.resultBody}>
                      <Text style={styles.resultTitle} numberOfLines={2}>
                        {item.title || item.filename}
                      </Text>
                      <Text style={styles.resultMeta}>
                        {item.pagecount || 0} pages
                      </Text>
                    </View>
                  </TouchableOpacity>
                );
              }}
            />
          ) : query.trim() && !loading ? (
            <Text style={styles.emptyText}>{t('tankoubon.noArchivesFound')}</Text>
          ) : null}

          {selected.size > 0 ? (
            <TouchableOpacity
              style={styles.addButton}
              onPress={handleAdd}
              disabled={adding}>
              <Text style={styles.addButtonText}>
                {adding
                  ? t('common.loading')
                  : t('tankoubon.addSelected', {count: selected.size})}
              </Text>
            </TouchableOpacity>
          ) : null}
        </View>
      </View>
    </Modal>
  );
}

const styles = StyleSheet.create({
  overlay: {
    backgroundColor: 'rgba(0,0,0,0.5)',
    flex: 1,
    justifyContent: 'flex-end',
  },
  container: {
    backgroundColor: colors.background,
    borderTopLeftRadius: 16,
    borderTopRightRadius: 16,
    maxHeight: '80%',
    paddingBottom: 34,
    paddingHorizontal: 16,
    paddingTop: 12,
  },
  header: {
    alignItems: 'center',
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginBottom: 14,
  },
  title: {
    color: colors.text,
    fontSize: 17,
    fontWeight: '800',
  },
  closeText: {
    color: colors.primary,
    fontSize: 15,
    fontWeight: '600',
  },
  searchRow: {
    flexDirection: 'row',
    gap: 8,
    marginBottom: 12,
  },
  input: {
    backgroundColor: colors.surface,
    borderColor: colors.border,
    borderRadius: 8,
    borderWidth: StyleSheet.hairlineWidth,
    color: colors.text,
    flex: 1,
    fontSize: 15,
    paddingHorizontal: 12,
    paddingVertical: 10,
  },
  searchButton: {
    alignItems: 'center',
    backgroundColor: colors.primary,
    borderRadius: 8,
    justifyContent: 'center',
    paddingHorizontal: 16,
  },
  searchButtonText: {
    color: colors.white,
    fontSize: 14,
    fontWeight: '700',
  },
  loading: {
    paddingVertical: 24,
  },
  list: {
    maxHeight: 400,
  },
  listContent: {
    gap: 6,
  },
  resultItem: {
    alignItems: 'center',
    backgroundColor: colors.surface,
    borderColor: colors.border,
    borderRadius: 8,
    borderWidth: StyleSheet.hairlineWidth,
    flexDirection: 'row',
    gap: 10,
    padding: 12,
  },
  resultItemSelected: {
    borderColor: colors.primary,
    backgroundColor: colors.primaryMuted,
  },
  checkbox: {
    alignItems: 'center',
    borderColor: colors.borderStrong,
    borderRadius: 4,
    borderWidth: 2,
    height: 22,
    justifyContent: 'center',
    width: 22,
  },
  checkboxChecked: {
    color: colors.primary,
    fontWeight: '800',
  },
  resultBody: {
    flex: 1,
  },
  resultTitle: {
    color: colors.text,
    fontSize: 14,
    fontWeight: '600',
  },
  resultMeta: {
    color: colors.textMuted,
    fontSize: 12,
    marginTop: 2,
  },
  emptyText: {
    color: colors.textMuted,
    fontSize: 14,
    paddingVertical: 24,
    textAlign: 'center',
  },
  addButton: {
    alignItems: 'center',
    backgroundColor: colors.primary,
    borderRadius: 8,
    marginTop: 12,
    paddingVertical: 12,
  },
  addButtonText: {
    color: colors.white,
    fontSize: 15,
    fontWeight: '800',
  },
});
