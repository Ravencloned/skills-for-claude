// Turn a title into a URL slug: lowercase, words joined by single hyphens, no leading/trailing hyphens.
export function slug(title) {
  return title.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '');
}
