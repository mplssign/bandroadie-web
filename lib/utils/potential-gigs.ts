import type { GigMemberResponse } from '@/lib/types';

export interface PotentialGigMemberInfo {
  id: string;
  first_name?: string | null;
  last_name?: string | null;
}

export interface LabeledMember {
  id: string;
  label: string;
  respondedAt?: string;
  response?: 'yes' | 'no';
}

export interface PotentialGigSummary {
  yes: LabeledMember[];
  no: LabeledMember[];
  optional: LabeledMember[];
  notResponded: LabeledMember[];
  yesCount: number;
  noCount: number;
}

interface MemberIdentity {
  id: string;
  firstName: string | null;
  lastName: string | null;
}

function normalizeFirstName(value: string | null | undefined): string | null {
  if (!value) return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function normalizeLastName(value: string | null | undefined): string | null {
  if (!value) return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function fallbackLabel(id: string): string {
  return `Former Member ${id.slice(0, 4).toUpperCase()}`;
}

function buildIdentities(
  members: PotentialGigMemberInfo[],
  responses: GigMemberResponse[] = [],
  optionalIds: string[] = [],
): Map<string, MemberIdentity> {
  const map = new Map<string, MemberIdentity>();

  members.forEach((member) => {
    map.set(member.id, {
      id: member.id,
      firstName: normalizeFirstName(member.first_name ?? null),
      lastName: normalizeLastName(member.last_name ?? null),
    });
  });

  responses.forEach((response) => {
    if (map.has(response.band_member_id)) return;
    const first = normalizeFirstName(response.band_members?.users?.first_name ?? null);
    const last = normalizeLastName(response.band_members?.users?.last_name ?? null);
    map.set(response.band_member_id, {
      id: response.band_member_id,
      firstName: first,
      lastName: last,
    });
  });

  optionalIds.forEach((id) => {
    if (!map.has(id)) {
      map.set(id, {
        id,
        firstName: null,
        lastName: null,
      });
    }
  });

  return map;
}

export function buildMemberLabelMap(
  members: PotentialGigMemberInfo[],
  responses: GigMemberResponse[] = [],
  optionalIds: string[] = [],
): Map<string, string> {
  const identities = buildIdentities(members, responses, optionalIds);

  const firstNameCounts = new Map<string, number>();
  identities.forEach(({ firstName }) => {
    if (!firstName) return;
    const key = firstName.toLowerCase();
    firstNameCounts.set(key, (firstNameCounts.get(key) ?? 0) + 1);
  });

  const labels = new Map<string, string>();

  identities.forEach((identity, id) => {
    const { firstName, lastName } = identity;
    if (!firstName && !lastName) {
      labels.set(id, fallbackLabel(id));
      return;
    }

    if (!firstName) {
      labels.set(id, lastName ?? fallbackLabel(id));
      return;
    }

    const needsDisambiguation = (firstNameCounts.get(firstName.toLowerCase()) ?? 0) > 1;

    if (needsDisambiguation) {
      if (lastName) {
        labels.set(id, `${firstName} ${lastName.charAt(0).toUpperCase()}`);
      } else {
        labels.set(id, `${firstName} ${id.slice(0, 2).toUpperCase()}`);
      }
      return;
    }

    labels.set(id, firstName);
  });

  return labels;
}

export function getMemberResponse(
  responses: GigMemberResponse[] = [],
  memberId: string | null | undefined,
): 'yes' | 'no' | null {
  if (!memberId) return null;
  const match = responses.find((response) => response.band_member_id === memberId);
  return match ? match.response : null;
}

export function summarizeGigResponses(
  members: PotentialGigMemberInfo[],
  optionalIds: string[] = [],
  responses: GigMemberResponse[] = [],
): PotentialGigSummary {
  const optionalSet = new Set(optionalIds.filter(Boolean));
  const labels = buildMemberLabelMap(members, responses, optionalIds);
  const responseMap = new Map<string, GigMemberResponse>();
  responses.forEach((response) => {
    responseMap.set(response.band_member_id, response);
  });

  const yes: LabeledMember[] = [];
  const no: LabeledMember[] = [];
  const optional: LabeledMember[] = [];
  const notResponded: LabeledMember[] = [];

  members.forEach((member) => {
    const label = labels.get(member.id) ?? fallbackLabel(member.id);
    const record = responseMap.get(member.id);

    if (optionalSet.has(member.id)) {
      optional.push({
        id: member.id,
        label,
        respondedAt: record?.responded_at ?? undefined,
        response: record?.response,
      });
      return;
    }

    if (record?.response === 'yes') {
      yes.push({
        id: member.id,
        label,
        respondedAt: record.responded_at ?? undefined,
        response: 'yes',
      });
      return;
    }

    if (record?.response === 'no') {
      no.push({
        id: member.id,
        label,
        respondedAt: record.responded_at ?? undefined,
        response: 'no',
      });
      return;
    }

    notResponded.push({ id: member.id, label });
  });

  const yesCount = yes.length;
  const noCount = no.length;

  return {
    yes,
    no,
    optional,
    notResponded,
    yesCount,
    noCount,
  };
}

export function filterGigsForBand<T extends { band_id?: string | null }>(
  gigs: T[],
  bandId: string | null | undefined,
): T[] {
  if (!bandId) return [];
  return gigs.filter((gig) => gig.band_id === bandId);
}
