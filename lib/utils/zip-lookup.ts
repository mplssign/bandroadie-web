export interface ZipCodeData {
  city: string;
  state: string;
  stateAbbreviation: string;
}

export async function lookupZipCode(zip: string): Promise<ZipCodeData | null> {
  const cleanZip = zip.replace(/\D/g, '').substring(0, 5);
  
  if (cleanZip.length !== 5) {
    return null;
  }

  try {
    const response = await fetch(`https://api.zippopotam.us/us/${cleanZip}`);
    
    if (!response.ok) {
      return null;
    }

    const data = await response.json();
    
    if (!data.places || data.places.length === 0) {
      return null;
    }

    const place = data.places[0];
    
    return {
      city: place['place name'],
      state: place.state,
      stateAbbreviation: place['state abbreviation'],
    };
  } catch (error) {
    console.error('Error looking up ZIP code:', error);
    return null;
  }
}

export function formatCityState(zipData: ZipCodeData): string {
  return `${zipData.city}, ${zipData.stateAbbreviation}`;
}

const zipCache = new Map<string, ZipCodeData>();

export async function lookupZipCodeCached(zip: string): Promise<ZipCodeData | null> {
  const cleanZip = zip.replace(/\D/g, '').substring(0, 5);
  
  if (cleanZip.length !== 5) {
    return null;
  }

  if (zipCache.has(cleanZip)) {
    return zipCache.get(cleanZip)!;
  }

  const result = await lookupZipCode(cleanZip);
  
  if (result) {
    zipCache.set(cleanZip, result);
  }

  return result;
}
