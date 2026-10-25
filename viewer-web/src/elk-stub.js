// Stands in for elkjs (EPL-2.0), which tarn does not ship. Mermaid loads it only for the optional
// `layout: elk` setting; the default dagre layout never touches it.
export default class ELK {
  constructor() {
    throw new Error("The ELK layout is not available in tarn");
  }
}
