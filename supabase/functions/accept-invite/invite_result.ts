export type TokenInviteRow = {
  id: string;
  band_id: string;
  email: string;
  status: string;
  expires_at: string | null;
  bands?: { name?: string | null } | Array<{ name?: string | null }> | null;
};

export type TokenInviteClassification =
  | { kind: "not_found" }
  | { kind: "email_mismatch" }
  | { kind: "unavailable"; reason: "consumed" | "ineligible" | "expired" }
  | { kind: "eligible"; invite: TokenInviteRow };

export type TokenInviteResponse = {
  status: number;
  body: Record<string, unknown>;
};

export function classifyTokenInvite(
  row: TokenInviteRow | null,
  authEmail: string,
  now: Date,
): TokenInviteClassification {
  if (row == null) {
    return { kind: "not_found" };
  }

  if (row.email.toLowerCase() !== authEmail.toLowerCase()) {
    return { kind: "email_mismatch" };
  }

  if (row.status === "accepted") {
    return { kind: "unavailable", reason: "consumed" };
  }

  if (row.status !== "pending" && row.status !== "sent") {
    return { kind: "unavailable", reason: "ineligible" };
  }

  if (row.expires_at != null && new Date(row.expires_at) < now) {
    return { kind: "unavailable", reason: "expired" };
  }

  return { kind: "eligible", invite: row };
}

export function tokenInviteResponse(
  classification: TokenInviteClassification,
  options: { rpcFailed?: boolean } = {},
): TokenInviteResponse {
  if (classification.kind === "eligible") {
    if (options.rpcFailed) {
      return {
        status: 502,
        body: {
          error: "We couldn't finish accepting your invite. Please try again.",
          code: "accept_failed",
        },
      };
    }

    const bandRecord = Array.isArray(classification.invite.bands)
      ? classification.invite.bands[0]
      : classification.invite.bands;
    const bandName = bandRecord?.name ?? "Unknown";
    return {
      status: 200,
      body: {
        success: true,
        accepted_count: 1,
        band_names: [bandName],
        accepted_band_id: classification.invite.band_id,
        accepted_band_ids: [classification.invite.band_id],
      },
    };
  }

  if (classification.kind === "email_mismatch") {
    return {
      status: 403,
      body: {
        error: "This invite was sent to a different email.",
        code: "email_mismatch",
      },
    };
  }

  return {
    status: 409,
    body: {
      error: "This invite is no longer available.",
      code: "invite_unavailable",
    },
  };
}
