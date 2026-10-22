import { definePluginSettings } from "@api/Settings";
import definePlugin, { OptionType } from "@utils/types";
import { FluxDispatcher, MediaEngineStore, UserStore } from "@webpack/common";

const settings = definePluginSettings({
  profile: {
    description: "The input profile to switch to when Discord starts",
    type: OptionType.SELECT,
    options: [
      { label: "Voice Isolation", value: "VOICE_ISOLATION" },
      { label: "Studio", value: "STUDIO", default: true },
      { label: "Custom", value: "CUSTOM" },
    ],
  },
});

// Once per start, so a profile picked in a call is kept on reconnects.
let applied = false;

function apply(): void {
  if (applied) return;
  applied = true;
  const { profile } = settings.store;
  // Discord's types only know DEFAULT and CUSTOM.
  if ((MediaEngineStore.getActiveInputProfile() as string) === profile) return;
  FluxDispatcher.dispatch({
    type: "AUDIO_SET_ACTIVE_INPUT_PROFILE",
    inputProfile: profile,
  });
}

export default definePlugin({
  name: "InputProfile",
  description: "Switches the microphone to an input profile at startup.",
  authors: [{ name: "siku2", id: 0n }],
  settings,

  flux: {
    POST_CONNECTION_OPEN: apply,
  },

  start() {
    applied = false;
    if (UserStore.getCurrentUser()) apply();
  },
});
