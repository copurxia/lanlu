#!/usr/bin/env deno run --allow-read

import { BasePlugin, PluginInfo, PluginInput } from "../base_plugin.ts";

/**
 * Minimal Script plugin example.
 * - On run: emits a single log line "hello world" via NDJSON (stdio) then returns success.
 * - On plugin_info: returns metadata with type=script so scan_plugins will auto-register it to cron.
 */
class HelloWorldScriptPlugin extends BasePlugin {
  getPluginInfo(): PluginInfo {
    return {
      name: "Hello World",
      type: "script",
      namespace: "hello_script",
      author: "lrr4cj",
      version: "1.0",
      description: "Prints hello world to the task log and exits.",
      parameters: [],
      // Optional: cron defaults used on first auto-registration.
      cron_enabled: false,
      cron_expression: "0 0 * * *",
      cron_priority: 50,
      cron_timeout_seconds: 60,
    };
  }

  protected async runPlugin(_input: PluginInput): Promise<void> {
    await this.logInfo("hello world");
    this.outputResult({ success: true, data: { message: "hello world" } });
  }
}

await new HelloWorldScriptPlugin().handleCommand();

