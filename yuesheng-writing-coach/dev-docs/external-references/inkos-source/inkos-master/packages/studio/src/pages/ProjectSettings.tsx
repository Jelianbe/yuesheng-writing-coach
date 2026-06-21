import { useEffect, useState } from "react";
import { Bell, Bot, Radar, Settings2, Plus, Trash2 } from "lucide-react";
import { fetchJson, putApi, useApi } from "../hooks/use-api";
import type { Theme } from "../hooks/use-theme";
import type { TFunction } from "../hooks/use-i18n";
import { useColors } from "../hooks/use-colors";
import {
  buildDetectionConfig,
  buildNotifyChannel,
  DEFAULT_DETECTION,
  detectionDraftFromConfig,
  notifyDraftFromChannel,
  NOTIFY_TYPES,
  type DetectionDraft,
  type NotifyChannelDraft,
  type NotifyType,
  type OverrideRow,
} from "./project-settings-model";

interface Nav {
  toDashboard: () => void;
  toServices: () => void;
}

type NoticeTone = "success" | "error" | "info";

// Smooth open/close via grid-template-rows (same trick as the sidebar).
function Collapse({ open, children }: { open: boolean; children: React.ReactNode }) {
  return (
    <div className={`grid transition-[grid-template-rows] duration-200 ease-out ${open ? "grid-rows-[1fr]" : "grid-rows-[0fr]"}`}>
      <div className="overflow-hidden">{children}</div>
    </div>
  );
}

function SettingsCard({
  title,
  description,
  icon,
  children,
}: {
  title: string;
  description: string;
  icon: React.ReactNode;
  children: React.ReactNode;
}) {
  return (
    <section className="rounded-2xl border border-border/50 bg-card/70 p-5 shadow-sm space-y-4">
      <div className="flex items-start gap-3">
        <div className="mt-0.5 rounded-xl bg-primary/10 p-2 text-primary">{icon}</div>
        <div>
          <h2 className="text-base font-bold">{title}</h2>
          <p className="mt-1 text-sm text-muted-foreground leading-relaxed">{description}</p>
        </div>
      </div>
      {children}
    </section>
  );
}

const fieldClass = "w-full rounded-lg border border-border bg-secondary/30 px-3 py-2 text-sm outline-none focus:border-primary/50";

export function ProjectSettings({ nav, theme, t }: { nav: Nav; theme: Theme; t: TFunction }) {
  const c = useColors(theme);
  const { data: overridesData, refetch: refetchOverrides } = useApi<{ overrides: Record<string, unknown> }>("/project/model-overrides");
  const { data: notifyData, refetch: refetchNotify } = useApi<{ channels: unknown[] }>("/project/notify");
  const { data: modeData, refetch: refetchMode } = useApi<{ mode: "legacy" | "v2" }>("/project/input-governance-mode");
  const { data: detectionData, refetch: refetchDetection } = useApi<{ detection: unknown | null }>("/project/detection");
  const [mode, setMode] = useState<"legacy" | "v2">("v2");
  const [overrideRows, setOverrideRows] = useState<OverrideRow[]>([]);
  const [notifyChannels, setNotifyChannels] = useState<NotifyChannelDraft[]>([]);
  const [det, setDet] = useState<DetectionDraft>({ ...DEFAULT_DETECTION });
  const [notice, setNotice] = useState<{ tone: NoticeTone; message: string } | null>(null);
  const [saving, setSaving] = useState<string | null>(null);

  useEffect(() => {
    if (modeData?.mode) setMode(modeData.mode);
  }, [modeData]);

  useEffect(() => {
    if (!overridesData) return;
    setOverrideRows(Object.entries(overridesData.overrides ?? {}).map(([agent, val]) => {
      if (typeof val === "string") return { agent, model: val };
      const { model, ...rest } = (val ?? {}) as { model?: string };
      return { agent, model: model ?? "", rest };
    }));
  }, [overridesData]);

  useEffect(() => {
    if (!notifyData) return;
    setNotifyChannels((notifyData.channels ?? []).map(notifyDraftFromChannel));
  }, [notifyData]);

  useEffect(() => {
    if (!detectionData) return;
    setDet(detectionDraftFromConfig(detectionData.detection));
  }, [detectionData]);

  const runSave = async (key: string, work: () => Promise<void>, success: string) => {
    setSaving(key);
    setNotice(null);
    try {
      await work();
      setNotice({ tone: "success", message: success });
    } catch (e) {
      setNotice({ tone: "error", message: e instanceof Error ? e.message : String(e) });
    } finally {
      setSaving(null);
    }
  };

  const updateChannel = (index: number, patch: Partial<NotifyChannelDraft>) => {
    setNotifyChannels((prev) => prev.map((ch, i) => (i === index ? { ...ch, ...patch } : ch)));
  };

  return (
    <div className="space-y-8">
      <div className="flex items-center gap-2 text-sm text-muted-foreground">
        <button onClick={nav.toDashboard} className={c.link}>{t("bread.home")}</button>
        <span className="text-border">/</span>
        <span>{t("settings.title")}</span>
      </div>

      <div className="space-y-2">
        <h1 className="font-serif text-3xl flex items-center gap-3">
          <Settings2 size={28} className="text-primary" />
          {t("settings.title")}
        </h1>
        <p className="text-sm text-muted-foreground">{t("settings.subtitle")}</p>
      </div>

      {notice && (
        <div
          className={`rounded-xl px-4 py-3 text-sm ${
            notice.tone === "error"
              ? "bg-destructive/10 text-destructive"
              : notice.tone === "info"
                ? "bg-secondary text-muted-foreground"
                : "bg-emerald-500/10 text-emerald-600"
          }`}
        >
          {notice.message}
        </div>
      )}

      <SettingsCard title={t("settings.inputGovernance")} description={t("settings.inputGovernanceHint")} icon={<Radar size={18} />}>
        <div className="flex flex-wrap items-center gap-3">
          <select
            value={mode}
            onChange={(e) => setMode(e.target.value === "legacy" ? "legacy" : "v2")}
            className="rounded-lg border border-border bg-secondary/30 px-3 py-2 text-sm outline-none"
          >
            <option value="v2">v2</option>
            <option value="legacy">legacy</option>
          </select>
          <button
            onClick={() => runSave("mode", async () => {
              await putApi("/project/input-governance-mode", { mode });
              await refetchMode();
            }, t("settings.saved"))}
            disabled={saving === "mode"}
            className={`rounded-lg px-4 py-2 text-sm font-bold ${c.btnPrimary} disabled:opacity-40`}
          >
            {saving === "mode" ? t("config.saving") : t("config.save")}
          </button>
        </div>
      </SettingsCard>

      {/* Model routing — per-agent model overrides */}
      <SettingsCard title={t("settings.modelOverrides")} description={t("settings.modelOverridesHint")} icon={<Bot size={18} />}>
        <div className="space-y-2">
          {overrideRows.length === 0 && (
            <p className="text-xs text-muted-foreground italic">{t("settings.noOverrides")}</p>
          )}
          {overrideRows.map((row, i) => (
            <div key={i} className="flex items-center gap-2">
              <input
                value={row.agent}
                onChange={(e) => setOverrideRows((prev) => prev.map((r, j) => (j === i ? { ...r, agent: e.target.value } : r)))}
                placeholder={t("settings.agentName")}
                className={`${fieldClass} flex-1`}
              />
              <span className="text-muted-foreground">→</span>
              <input
                value={row.model}
                onChange={(e) => setOverrideRows((prev) => prev.map((r, j) => (j === i ? { ...r, model: e.target.value } : r)))}
                placeholder={t("settings.modelId")}
                className={`${fieldClass} flex-1 font-mono`}
              />
              <button
                onClick={() => setOverrideRows((prev) => prev.filter((_, j) => j !== i))}
                className="shrink-0 rounded-lg p-2 text-muted-foreground hover:bg-destructive/10 hover:text-destructive transition-colors"
                aria-label="remove"
              >
                <Trash2 size={15} />
              </button>
            </div>
          ))}
        </div>
        <div className="flex flex-wrap gap-2">
          <button
            onClick={() => setOverrideRows((prev) => [...prev, { agent: "", model: "" }])}
            className={`flex items-center gap-1.5 rounded-lg px-3 py-2 text-sm font-medium ${c.btnSecondary}`}
          >
            <Plus size={14} /> {t("settings.addOverride")}
          </button>
          <button
            onClick={() => runSave("overrides", async () => {
              const overrides: Record<string, unknown> = {};
              for (const r of overrideRows) {
                const agent = r.agent.trim();
                const model = r.model.trim();
                if (!agent || !model) continue;
                overrides[agent] = r.rest && Object.keys(r.rest).length > 0 ? { ...r.rest, model } : model;
              }
              await putApi("/project/model-overrides", { overrides });
              await refetchOverrides();
            }, t("settings.saved"))}
            disabled={saving === "overrides"}
            className={`rounded-lg px-4 py-2 text-sm font-bold ${c.btnPrimary} disabled:opacity-40`}
          >
            {saving === "overrides" ? t("config.saving") : t("config.save")}
          </button>
          <button onClick={nav.toServices} className={`rounded-lg px-4 py-2 text-sm font-bold ${c.btnSecondary}`}>
            {t("settings.openModelConfig")}
          </button>
        </div>
      </SettingsCard>

      {/* Notification channels */}
      <SettingsCard title={t("settings.notify")} description={t("settings.notifyHint")} icon={<Bell size={18} />}>
        <div className="space-y-3">
          {notifyChannels.length === 0 && (
            <p className="text-xs text-muted-foreground italic">{t("settings.noChannels")}</p>
          )}
          {notifyChannels.map((ch, i) => (
            <div key={i} className="rounded-xl border border-border/60 bg-secondary/20 p-3 space-y-2">
              <div className="flex items-center gap-2">
                <select
                  value={ch.type}
                  onChange={(e) => updateChannel(i, { type: e.target.value as NotifyType })}
                  className="rounded-lg border border-border bg-background px-3 py-1.5 text-sm outline-none"
                >
                  {NOTIFY_TYPES.map((nt) => <option key={nt.value} value={nt.value}>{nt.label}</option>)}
                </select>
                <div className="flex-1" />
                <button
                  onClick={() => setNotifyChannels((prev) => prev.filter((_, j) => j !== i))}
                  className="rounded-lg p-1.5 text-muted-foreground hover:bg-destructive/10 hover:text-destructive transition-colors"
                  aria-label="remove"
                >
                  <Trash2 size={15} />
                </button>
              </div>
              {ch.type === "telegram" && (
                <div className="grid grid-cols-2 gap-2">
                  <input value={ch.botToken ?? ""} onChange={(e) => updateChannel(i, { botToken: e.target.value })} placeholder="botToken" className={`${fieldClass} font-mono`} />
                  <input value={ch.chatId ?? ""} onChange={(e) => updateChannel(i, { chatId: e.target.value })} placeholder="chatId" className={`${fieldClass} font-mono`} />
                </div>
              )}
              {(ch.type === "feishu" || ch.type === "wechat-work") && (
                <input value={ch.webhookUrl ?? ""} onChange={(e) => updateChannel(i, { webhookUrl: e.target.value })} placeholder="webhookUrl" className={`${fieldClass} font-mono`} />
              )}
              {ch.type === "webhook" && (
                <div className="grid grid-cols-2 gap-2">
                  <input value={ch.url ?? ""} onChange={(e) => updateChannel(i, { url: e.target.value })} placeholder="url" className={`${fieldClass} font-mono`} />
                  <input value={ch.secret ?? ""} onChange={(e) => updateChannel(i, { secret: e.target.value })} placeholder="secret (可选)" className={`${fieldClass} font-mono`} />
                </div>
              )}
            </div>
          ))}
        </div>
        <div className="flex gap-2">
          <button
            onClick={() => setNotifyChannels((prev) => [...prev, { type: "feishu" }])}
            className={`flex items-center gap-1.5 rounded-lg px-3 py-2 text-sm font-medium ${c.btnSecondary}`}
          >
            <Plus size={14} /> {t("settings.addChannel")}
          </button>
          <button
            onClick={() => runSave("notify", async () => {
              await putApi("/project/notify", { channels: notifyChannels.map(buildNotifyChannel) });
              await refetchNotify();
            }, t("settings.saved"))}
            disabled={saving === "notify"}
            className={`rounded-lg px-4 py-2 text-sm font-bold ${c.btnPrimary} disabled:opacity-40`}
          >
            {saving === "notify" ? t("config.saving") : t("config.save")}
          </button>
        </div>
      </SettingsCard>

      {/* AIGC detection */}
      <SettingsCard title={t("settings.detection")} description={t("settings.detectionHint")} icon={<Radar size={18} />}>
        <label className="flex items-center gap-2 text-sm">
          <input type="checkbox" checked={det.enabled} onChange={(e) => setDet((d) => ({ ...d, enabled: e.target.checked }))} />
          {t("settings.detectionEnable")}
        </label>
        <Collapse open={det.enabled}>
          <div className="space-y-2 pt-1">
            <div className="grid grid-cols-2 gap-2">
              <label className="text-xs text-muted-foreground space-y-1">
                <span>{t("settings.detectionProvider")}</span>
                <select value={det.provider} onChange={(e) => setDet((d) => ({ ...d, provider: e.target.value }))} className={fieldClass}>
                  <option value="custom">custom</option>
                  <option value="gptzero">gptzero</option>
                  <option value="originality">originality</option>
                </select>
              </label>
              <label className="text-xs text-muted-foreground space-y-1">
                <span>{t("settings.detectionApiKeyEnv")}</span>
                <input value={det.apiKeyEnv} onChange={(e) => setDet((d) => ({ ...d, apiKeyEnv: e.target.value }))} placeholder="DETECTOR_API_KEY" className={`${fieldClass} font-mono`} />
              </label>
            </div>
            <label className="text-xs text-muted-foreground space-y-1 block">
              <span>{t("settings.detectionApiUrl")}</span>
              <input value={det.apiUrl} onChange={(e) => setDet((d) => ({ ...d, apiUrl: e.target.value }))} placeholder="https://..." className={`${fieldClass} font-mono`} />
            </label>
            <div className="grid grid-cols-2 gap-2">
              <label className="text-xs text-muted-foreground space-y-1">
                <span>{t("settings.detectionThreshold")} (0–1)</span>
                <input type="number" min={0} max={1} step={0.05} value={det.threshold} onChange={(e) => setDet((d) => ({ ...d, threshold: Number(e.target.value) }))} className={fieldClass} />
              </label>
              <label className="text-xs text-muted-foreground space-y-1">
                <span>{t("settings.detectionMaxRetries")} (1–10)</span>
                <input type="number" min={1} max={10} step={1} value={det.maxRetries} onChange={(e) => setDet((d) => ({ ...d, maxRetries: Number(e.target.value) }))} className={fieldClass} />
              </label>
            </div>
            <label className="flex items-center gap-2 text-sm">
              <input type="checkbox" checked={det.autoRewrite} onChange={(e) => setDet((d) => ({ ...d, autoRewrite: e.target.checked }))} />
              {t("settings.detectionAutoRewrite")}
            </label>
          </div>
        </Collapse>
        <button
          onClick={() => runSave("detection", async () => {
            const payload = { detection: buildDetectionConfig(det) };
            await fetchJson("/project/detection", {
              method: "PUT",
              headers: { "Content-Type": "application/json" },
              body: JSON.stringify(payload),
            });
            await refetchDetection();
          }, t("settings.saved"))}
          disabled={saving === "detection"}
          className={`rounded-lg px-4 py-2 text-sm font-bold ${c.btnPrimary} disabled:opacity-40`}
        >
          {saving === "detection" ? t("config.saving") : t("config.save")}
        </button>
      </SettingsCard>
    </div>
  );
}
