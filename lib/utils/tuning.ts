import { TuningType } from '@/lib/types';

export interface TuningInfo {
  name: string;
  notes: string;
  color: string;
  popularity: number; // Lower number = more popular
  aliases: string[]; // Alternative names for bulk paste normalization
}

// Ordered by popularity in rock/grunge/pop/country music
export const tuningMap: Record<TuningType, TuningInfo> = {
  standard: {
    name: 'Standard',
    notes: 'E A D G B E',
    color: 'bg-blue-600 hover:bg-blue-700',
    popularity: 1,
    aliases: ['Standard', 'Standard Tuning', 'E', 'EADGBE', 'std', 'standard']
  },
  half_step: {
    name: 'Half Step',
    notes: 'Eb Ab Db Gb Bb Eb',
    color: 'bg-purple-600 hover:bg-purple-700',
    popularity: 2,
    aliases: ['Half Step Down', 'Half Step', 'Eb Standard', 'Eb', 'Half', '1/2 Step', 'semitone', 'half_step']
  },
  drop_d: {
    name: 'Drop D',
    notes: 'D A D G B E',
    color: 'bg-green-600 hover:bg-green-700',
    popularity: 3,
    aliases: ['Drop D', 'DADGBE', 'drop d', 'drop_d']
  },
  full_step: {
    name: 'Full Step',
    notes: 'D G C F A D',
    color: 'bg-orange-600 hover:bg-orange-700',
    popularity: 4,
    aliases: ['Full Step Down', 'Full Step', 'D Standard', 'Whole Step', 'Full', 'tone', 'full_step']
  },
  drop_c: {
    name: 'Drop C',
    notes: 'C G C F A D',
    color: 'bg-red-600 hover:bg-red-700',
    popularity: 5,
    aliases: ['Drop C', 'CGCFAD', 'drop c', 'drop_c']
  },
  drop_b: {
    name: 'Drop B',
    notes: 'B F# B E G# C#',
    color: 'bg-pink-600 hover:bg-pink-700',
    popularity: 6,
    aliases: ['Drop B', 'BF#BEG#C#', 'drop b', 'drop_b']
  },
  dadgad: {
    name: 'DADGAD',
    notes: 'D A D G A D',
    color: 'bg-indigo-600 hover:bg-indigo-700',
    popularity: 7,
    aliases: ['DADGAD', 'dadgad', 'Celtic Tuning']
  },
  open_g: {
    name: 'Open G',
    notes: 'D G D G B D',
    color: 'bg-teal-600 hover:bg-teal-700',
    popularity: 8,
    aliases: ['Open G', 'DGDGBD', 'open g', 'open_g']
  },
  open_d: {
    name: 'Open D',
    notes: 'D A D F# A D',
    color: 'bg-cyan-600 hover:bg-cyan-700',
    popularity: 9,
    aliases: ['Open D', 'DADF#AD', 'open d', 'open_d']
  },
  open_e: {
    name: 'Open E',
    notes: 'E B E G# B E',
    color: 'bg-amber-600 hover:bg-amber-700',
    popularity: 10,
    aliases: ['Open E', 'EBEG#BE', 'open e', 'open_e']
  }
};

// Get all tunings ordered by popularity
export function getTuningsOrderedByPopularity(): Array<{ type: TuningType; info: TuningInfo }> {
  return Object.entries(tuningMap)
    .map(([type, info]) => ({ type: type as TuningType, info }))
    .sort((a, b) => a.info.popularity - b.info.popularity);
}

export function getTuningInfo(tuning: TuningType): TuningInfo {
  return tuningMap[tuning] || tuningMap.standard;
}

export function getTuningName(tuning: TuningType): string {
  return getTuningInfo(tuning).name;
}

export function getTuningNotes(tuning: TuningType): string {
  return getTuningInfo(tuning).notes;
}

export function getTuningColor(tuning: TuningType): string {
  return getTuningInfo(tuning).color;
}

// Normalize tuning string to canonical TuningType
export function normalizeTuning(input: string): TuningType {
  const cleanInput = input.trim().toLowerCase();
  
  // Find matching tuning by checking aliases
  for (const [tuningType, info] of Object.entries(tuningMap)) {
    if (info.aliases.some(alias => alias.toLowerCase() === cleanInput)) {
      return tuningType as TuningType;
    }
  }
  
  // Fallback to standard if no match found
  return 'standard';
}

// Get display string for dropdown (bold name + notes in parentheses)
export function getTuningDisplayString(tuning: TuningType): string {
  const info = getTuningInfo(tuning);
  return `${info.name} (${info.notes})`;
}