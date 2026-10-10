import { findByPropsLazy, findStoreLazy } from "@webpack";
import {
  ChannelStore,
  GuildMemberStore,
  GuildStore,
  MediaEngineStore,
  SelectedChannelStore,
  UserStore,
  VoiceStateStore,
} from "@webpack/common";
import type { Command } from "./bridge.ts";
import type { Discord } from "./snapshot.ts";

interface ChangeSource {
  addChangeListener(listener: () => void): void;
  removeChangeListener(listener: () => void): void;
}

const SpeakingStore: ChangeSource & { isSpeaking(userId: string): boolean } =
  findStoreLazy("SpeakingStore");

const VoiceActions: { toggleSelfMute(): void; toggleSelfDeaf(): void } =
  findByPropsLazy("toggleSelfMute", "toggleSelfDeaf");

const ChannelActions: { selectVoiceChannel(id: string | null): void } =
  findByPropsLazy("selectVoiceChannel", "selectChannel");

/** Every store the snapshot reads from. */
export const sources = (): ChangeSource[] => [
  SelectedChannelStore,
  VoiceStateStore,
  MediaEngineStore,
  ChannelStore,
  GuildStore,
  GuildMemberStore,
  UserStore,
  SpeakingStore,
];

export const discord: Discord = {
  selfId: () => UserStore.getCurrentUser()?.id,
  selfMuted: () => MediaEngineStore.isSelfMute(),
  selfDeafened: () => MediaEngineStore.isSelfDeaf(),
  voiceChannelId: () => SelectedChannelStore.getVoiceChannelId(),
  channel: (id) => {
    const channel = ChannelStore.getChannel(id);
    if (!channel) return undefined;
    return {
      id: channel.id,
      name: channel.name,
      guildId: channel.guild_id || null,
      recipientIds: channel.recipients ?? [],
    };
  },
  guildName: (id) => GuildStore.getGuild(id)?.name,
  voiceStates: (channelId) =>
    Object.values(VoiceStateStore.getVoiceStatesForChannel(channelId)),
  user: (id) => {
    const user = UserStore.getUser(id);
    if (!user) return undefined;
    return {
      id: user.id,
      username: user.username,
      globalName: user.globalName,
      avatarUrl: (guildId, size) => user.getAvatarURL(guildId, size, false),
    };
  },
  nick: (guildId, userId) => GuildMemberStore.getNick(guildId, userId),
  speaking: (userId) => SpeakingStore.isSpeaking(userId),
  locallyMuted: (userId) => MediaEngineStore.isLocalMute(userId),
};

/** Discord only offers toggles, so they fire only when the state differs. */
export function run(command: Command): void {
  switch (command.kind) {
    case "setMute":
      if (MediaEngineStore.isSelfMute() !== command.muted) {
        VoiceActions.toggleSelfMute();
      }
      break;
    case "setDeafen":
      if (MediaEngineStore.isSelfDeaf() !== command.deafened) {
        VoiceActions.toggleSelfDeaf();
      }
      break;
    case "leaveCall":
      ChannelActions.selectVoiceChannel(null);
      break;
  }
}
