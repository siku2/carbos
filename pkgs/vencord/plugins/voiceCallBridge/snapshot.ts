import type {
  Call,
  Image,
  Participant,
  State,
} from "./io.siku2.VoiceCall.varlink.ts";

export const avatarSizes = [32, 64, 128, 256];

export interface VoiceState {
  readonly userId: string;
  readonly selfMute: boolean;
  readonly selfDeaf: boolean;
  readonly mute: boolean;
  readonly deaf: boolean;
  /** Not allowed to speak on a stage. */
  readonly suppress: boolean;
}

export interface User {
  readonly id: string;
  readonly username: string;
  readonly globalName: string | undefined;
  /** The server avatar if there is one. */
  avatarUrl(guildId: string | null, size: number): string;
}

export interface Channel {
  readonly id: string;
  readonly name: string;
  readonly guildId: string | null;
  readonly recipientIds: readonly string[];
}

/** The parts of Discord the state is built from. */
export interface Discord {
  selfId(): string | undefined;
  selfMuted(): boolean;
  selfDeafened(): boolean;
  voiceChannelId(): string | null | undefined;
  channel(id: string): Channel | undefined;
  guildName(id: string): string | undefined;
  voiceStates(channelId: string): readonly VoiceState[];
  user(id: string): User | undefined;
  nick(guildId: string, userId: string): string | null | undefined;
  speaking(userId: string): boolean;
  locallyMuted(userId: string): boolean;
}

export function snapshot(discord: Discord): State {
  return {
    muted: discord.selfMuted(),
    deafened: discord.selfDeafened(),
    call: currentCall(discord),
  };
}

function currentCall(discord: Discord): Call | null {
  const id = discord.voiceChannelId();
  const channel = id ? discord.channel(id) : undefined;
  if (channel === undefined) return null;

  const { guildId } = channel;
  const selfId = discord.selfId();
  const name = (userId: string) => {
    const user = discord.user(userId);
    return (
      (guildId && discord.nick(guildId, userId)) ||
      user?.globalName ||
      user?.username ||
      userId
    );
  };

  const participants = discord
    .voiceStates(channel.id)
    .map(
      (state): Participant => ({
        id: state.userId,
        name: name(state.userId),
        avatar: avatar(discord.user(state.userId), guildId),
        speaking: discord.speaking(state.userId),
        selfMuted: state.selfMute,
        selfDeafened: state.selfDeaf,
        serverMuted: state.mute || state.suppress,
        serverDeafened: state.deaf,
        locallyMuted:
          state.userId !== selfId && discord.locallyMuted(state.userId),
        self: state.userId === selfId,
      }),
    )
    .sort((a, b) => a.name.localeCompare(b.name));

  return {
    id: channel.id,
    name: channel.name || channel.recipientIds.map(name).join(", "),
    server: guildId ? (discord.guildName(guildId) ?? null) : null,
    participants,
  };
}

function avatar(user: User | undefined, guildId: string | null): Image[] {
  if (user === undefined) return [];
  return avatarSizes.map((size) => ({
    url: user.avatarUrl(guildId, size),
    width: size,
    height: size,
  }));
}
