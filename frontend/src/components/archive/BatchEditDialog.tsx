"use client";

import { useMemo, useState } from "react";
import { Dialog, DialogBody, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { parseTags } from "@/lib/utils/tag-utils";

export type BatchEditScope = "all" | "archive" | "tankoubon";
export type SummaryMode = "append" | "replace" | "clear";

export interface BatchEditPayload {
  scope: BatchEditScope;
  updateTitle: boolean;
  titlePrefix: string;
  titleSuffix: string;
  updateSummary: boolean;
  summaryMode: SummaryMode;
  summaryValue: string;
  updateTags: boolean;
  tagsAdd: string[];
  tagsRemove: string[];
  runMetadataPlugin: boolean;
  metadataPluginNamespace: string;
  metadataPluginParam: string;
}

interface BatchEditDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  totalSelected: number;
  selectedArchiveCount: number;
  selectedTankoubonCount: number;
  metadataPluginOptions: Array<{ namespace: string; name: string }>;
  applying?: boolean;
  t: (key: string) => string;
  onApply: (payload: BatchEditPayload) => Promise<boolean>;
}

export function BatchEditDialog({
  open,
  onOpenChange,
  totalSelected,
  selectedArchiveCount,
  selectedTankoubonCount,
  metadataPluginOptions,
  applying = false,
  t,
  onApply,
}: BatchEditDialogProps) {
  const [scope, setScope] = useState<BatchEditScope>("all");
  const [updateTitle, setUpdateTitle] = useState(false);
  const [titlePrefix, setTitlePrefix] = useState("");
  const [titleSuffix, setTitleSuffix] = useState("");
  const [updateSummary, setUpdateSummary] = useState(false);
  const [summaryMode, setSummaryMode] = useState<SummaryMode>("append");
  const [summaryValue, setSummaryValue] = useState("");
  const [updateTags, setUpdateTags] = useState(false);
  const [tagsAddRaw, setTagsAddRaw] = useState("");
  const [tagsRemoveRaw, setTagsRemoveRaw] = useState("");
  const [runMetadataPlugin, setRunMetadataPlugin] = useState(false);
  const [metadataPluginNamespace, setMetadataPluginNamespace] = useState("");
  const [metadataPluginParam, setMetadataPluginParam] = useState("");

  const effectiveArchiveCount = scope === "tankoubon" ? 0 : selectedArchiveCount;
  const effectiveTankCount = scope === "archive" ? 0 : selectedTankoubonCount;
  const effectiveTotalCount = effectiveArchiveCount + effectiveTankCount;
  const hasAnyFieldEnabled = updateTitle || updateSummary || updateTags || runMetadataPlugin;
  const pluginReady = !runMetadataPlugin || metadataPluginNamespace.trim().length > 0;

  const tagsAdd = useMemo(() => parseTags(tagsAddRaw), [tagsAddRaw]);
  const tagsRemove = useMemo(() => parseTags(tagsRemoveRaw), [tagsRemoveRaw]);

  const summaryLines = useMemo(() => {
    const lines: string[] = [];
    if (updateTitle && (titlePrefix.trim() || titleSuffix.trim())) {
      lines.push(
        `${t("home.batchEditTitleField")}: +${titlePrefix.trim() || "''"} / +${titleSuffix.trim() || "''"}`
      );
    }
    if (updateSummary) {
      const modeLabel =
        summaryMode === "append"
          ? t("home.batchSummaryAppend")
          : summaryMode === "replace"
            ? t("home.batchSummaryReplace")
            : t("home.batchSummaryClear");
      lines.push(`${t("archive.summary")}: ${modeLabel}`);
    }
    if (updateTags) {
      lines.push(`${t("archive.tags")}: +${tagsAdd.length} / -${tagsRemove.length}`);
    }
    if (runMetadataPlugin) {
      lines.push(
        `${t("home.batchMetadataPluginField")}: ${metadataPluginNamespace || t("home.batchMetadataPluginNotSelected")}`
      );
    }
    return lines;
  }, [metadataPluginNamespace, runMetadataPlugin, summaryMode, t, tagsAdd.length, tagsRemove.length, titlePrefix, titleSuffix, updateSummary, updateTags, updateTitle]);

  const handleApply = async () => {
    const applied = await onApply({
      scope,
      updateTitle,
      titlePrefix,
      titleSuffix,
      updateSummary,
      summaryMode,
      summaryValue,
      updateTags,
      tagsAdd,
      tagsRemove,
      runMetadataPlugin,
      metadataPluginNamespace,
      metadataPluginParam,
    });
    if (applied) onOpenChange(false);
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent size="lg">
        <DialogHeader>
          <DialogTitle>{t("home.batchEditTitle")}</DialogTitle>
        </DialogHeader>
        <DialogBody className="space-y-5">
          <div className="rounded-md border p-3 text-sm space-y-1">
            <div className="font-medium">
              {t("common.selected")}: {totalSelected}
            </div>
            <div className="text-muted-foreground text-xs">
              Archive: {selectedArchiveCount} / Tankoubon: {selectedTankoubonCount}
            </div>
          </div>

          <div className="space-y-2">
            <label className="text-sm font-medium">{t("home.batchScopeLabel")}</label>
            <Select value={scope} onValueChange={(value) => setScope(value as BatchEditScope)}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">{t("home.batchScopeAll")}</SelectItem>
                <SelectItem value="archive">{t("home.batchScopeArchive")}</SelectItem>
                <SelectItem value="tankoubon">{t("home.batchScopeTankoubon")}</SelectItem>
              </SelectContent>
            </Select>
          </div>

          <div className="space-y-3 rounded-md border p-3">
            <label className="flex items-center gap-2 text-sm font-medium">
              <Checkbox checked={updateTitle} onCheckedChange={(checked) => setUpdateTitle(Boolean(checked))} />
              {t("home.batchEditTitleField")}
            </label>
            {updateTitle && (
              <div className="grid gap-2 sm:grid-cols-2">
                <Input
                  value={titlePrefix}
                  onChange={(e) => setTitlePrefix(e.target.value)}
                  placeholder={t("home.batchTitlePrefixPlaceholder")}
                />
                <Input
                  value={titleSuffix}
                  onChange={(e) => setTitleSuffix(e.target.value)}
                  placeholder={t("home.batchTitleSuffixPlaceholder")}
                />
              </div>
            )}
          </div>

          <div className="space-y-3 rounded-md border p-3">
            <label className="flex items-center gap-2 text-sm font-medium">
              <Checkbox checked={updateSummary} onCheckedChange={(checked) => setUpdateSummary(Boolean(checked))} />
              {t("archive.summary")}
            </label>
            {updateSummary && (
              <div className="space-y-2">
                <Select value={summaryMode} onValueChange={(value) => setSummaryMode(value as SummaryMode)}>
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="append">{t("home.batchSummaryAppend")}</SelectItem>
                    <SelectItem value="replace">{t("home.batchSummaryReplace")}</SelectItem>
                    <SelectItem value="clear">{t("home.batchSummaryClear")}</SelectItem>
                  </SelectContent>
                </Select>
                {summaryMode !== "clear" && (
                  <Textarea
                    value={summaryValue}
                    onChange={(e) => setSummaryValue(e.target.value)}
                    placeholder={t("home.batchSummaryPlaceholder")}
                    rows={3}
                  />
                )}
              </div>
            )}
          </div>

          <div className="space-y-3 rounded-md border p-3">
            <label className="flex items-center gap-2 text-sm font-medium">
              <Checkbox checked={updateTags} onCheckedChange={(checked) => setUpdateTags(Boolean(checked))} />
              {t("archive.tags")}
            </label>
            {updateTags && (
              <div className="grid gap-2 sm:grid-cols-2">
                <Input
                  value={tagsAddRaw}
                  onChange={(e) => setTagsAddRaw(e.target.value)}
                  placeholder={t("home.batchTagsAddPlaceholder")}
                />
                <Input
                  value={tagsRemoveRaw}
                  onChange={(e) => setTagsRemoveRaw(e.target.value)}
                  placeholder={t("home.batchTagsRemovePlaceholder")}
                />
              </div>
            )}
          </div>

          <div className="space-y-3 rounded-md border p-3">
            <label className="flex items-center gap-2 text-sm font-medium">
              <Checkbox checked={runMetadataPlugin} onCheckedChange={(checked) => setRunMetadataPlugin(Boolean(checked))} />
              {t("home.batchMetadataPluginField")}
            </label>
            {runMetadataPlugin && (
              <div className="space-y-2">
                <Select value={metadataPluginNamespace} onValueChange={setMetadataPluginNamespace}>
                  <SelectTrigger>
                    <SelectValue placeholder={t("archive.metadataPluginSelectPlaceholder")} />
                  </SelectTrigger>
                  <SelectContent>
                    {metadataPluginOptions.length > 0 ? (
                      metadataPluginOptions.map((plugin) => (
                        <SelectItem key={plugin.namespace} value={plugin.namespace}>
                          {plugin.name} ({plugin.namespace})
                        </SelectItem>
                      ))
                    ) : (
                      <div className="px-2 py-1.5 text-sm text-muted-foreground">
                        {t("archive.metadataPluginNoPlugins")}
                      </div>
                    )}
                  </SelectContent>
                </Select>
                <Input
                  value={metadataPluginParam}
                  onChange={(e) => setMetadataPluginParam(e.target.value)}
                  placeholder={t("archive.metadataPluginParamPlaceholder")}
                />
              </div>
            )}
          </div>

          <div className="rounded-md border p-3 text-xs text-muted-foreground space-y-1">
            <div className="font-medium text-foreground">
              {t("home.batchPreviewTarget").replace("{count}", String(effectiveTotalCount))}
            </div>
            {summaryLines.length > 0 ? (
              summaryLines.map((line, index) => <div key={index}>• {line}</div>)
            ) : (
              <div>{t("home.batchEditNoFieldSelected")}</div>
            )}
          </div>
        </DialogBody>
        <DialogFooter>
          <Button variant="outline" onClick={() => onOpenChange(false)} disabled={applying}>
            {t("common.cancel")}
          </Button>
          <Button
            onClick={() => void handleApply()}
            disabled={!hasAnyFieldEnabled || !pluginReady || applying || effectiveTotalCount <= 0}
          >
            {applying
              ? t("common.loading")
              : t("home.batchApplyToCount").replace("{count}", String(effectiveTotalCount))}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
