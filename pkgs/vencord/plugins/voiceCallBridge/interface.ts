// Mirrors io.siku2.VoiceCall.varlink.

export interface Image {
  readonly url: string;
  readonly width: number;
  readonly height: number;
}

export interface Participant {
  readonly id: string;
  readonly name: string;
  readonly avatar: readonly Image[];
  readonly speaking: boolean;
  readonly selfMuted: boolean;
  readonly selfDeafened: boolean;
  readonly serverMuted: boolean;
  readonly serverDeafened: boolean;
  readonly locallyMuted: boolean;
  readonly self: boolean;
}

export interface Call {
  readonly id: string;
  readonly name: string;
  readonly server: string | null;
  readonly participants: readonly Participant[];
}

export interface State {
  readonly muted: boolean;
  readonly deafened: boolean;
  readonly call: Call | null;
}
