export default class WordData {
  id: number = 0
  article: string = '';
  word: string = '';
  meaning: string = '';
  example: string = '';
  learned: boolean = false

  constructor(
    id: number,
    article: string,
    word: string,
    meaning: string,
    example: string,
    learned: boolean
  ) {
    this.id = id
    this.article = article
    this.word = word
    this.meaning = meaning
    this.example = example
    this.learned = learned
  }

  public toString() {
    return `{ id: ${this.id}, ${this.article} ${this.word}, meaning: ${this.meaning}, example: ${this.example}, learned: ${this.learned}`
  }
}