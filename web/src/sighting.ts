// One quokka sighting, as GET /sightings returns it.
export interface Sighting {
  id: number;
  where: string;
  count: number;
  created: string;
}

const NUMBERS = ["no", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"];

// The count in words up to ten, in figures above it.
export function countWords(count: number): string {
  if (!Number.isInteger(count) || count < 0) {
    throw new RangeError(`A count must be a whole number of quokkas, not ${count}.`);
  }
  return count < NUMBERS.length ? NUMBERS[count] : String(count);
}

// The date of a sighting in Perth's time, as "3 November 2026".
export function perthDate(iso: string): string {
  const when = new Date(iso);
  if (Number.isNaN(when.getTime())) {
    throw new RangeError(`${iso} is not a date.`);
  }
  return new Intl.DateTimeFormat("en-AU", {
    timeZone: "Australia/Perth",
    day: "numeric",
    month: "long",
    year: "numeric",
  }).format(when);
}

// A sighting as one sentence: "Two quokkas at Thomson Bay on 3 November 2026."
export function describe(s: Sighting): string {
  const words = countWords(s.count);
  const noun = s.count === 1 ? "quokka" : "quokkas";
  const lead = words.charAt(0).toUpperCase() + words.slice(1);
  return `${lead} ${noun} at ${s.where.trim()} on ${perthDate(s.created)}.`;
}

// First change pushed through the hook.
