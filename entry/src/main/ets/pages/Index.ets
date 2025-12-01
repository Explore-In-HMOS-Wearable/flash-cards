import { DatabaseManager, DatabaseManagerParam, Remaining } from '../common/DatabaseManager';
import WordList from '../models/WordList';

@Entry
@Component
struct Index {
  pathStack: NavPathStack = new NavPathStack()
  ctx: Context | undefined = this.getUIContext().getHostContext()
  wordLists: WordList[] = [
    new WordList('A1 Deutsch', 'A1DeutschWortliste'),
    new WordList('A1 Deutsch Animals', 'A1DeutschTiere'),
    new WordList('A1 Deutsch Verbs', 'A1DeutschVerben'),
  ]
  @State selectedIndex: number = -1;
  @State remaining: Remaining = { learnedCount: 0, unlearnedCount: 0 };

  @Builder
  MyMenu() {
    Menu() {
      ForEach(this.wordLists, (wordList: WordList, index: number) => {
        MenuItem({ content: wordList.name })
          .onChange((selected: boolean) => {
            this.selectedIndex = index
          })
      },
        (wordList: WordList, index: number) => wordList.name)
    }
  }

  build() {
    Navigation(this.pathStack) {
      Column() {

        Text('Flash Cards')
          .fontColor(Color.Black)
          .fontStyle(FontStyle.Italic)
          .fontSize(28)
          .padding(10)

        Column() {
          Text(this.selectedIndex === -1 ? 'Click to select word list' : this.wordLists[this.selectedIndex].name)
            .fontSize(18)
            .fontColor(Color.Black)
            .fontWeight(FontWeight.Bold)
        }
        .bindMenu(this.MyMenu)
        .height(20)
        .background('#11ff30ff')
        .margin({ bottom: 10 })

        Button('Start')
          .onClick(async () => {
            let databaseManager: DatabaseManager = new DatabaseManager()
            try {
              console.info('Filename: ' + this.wordLists[this.selectedIndex].fileName)
              await databaseManager.createStore(this.ctx, this.wordLists[this.selectedIndex].fileName)
              let param: DatabaseManagerParam = { databaseManager: databaseManager }
              this.pathStack.pushPathByName('FlashCardsPage', param)
            } catch (e) {
              databaseManager.close();
              console.error(`Database error: ${e}`)
            }

          })
      }
      .height('100%')
      .width('100%')
      .justifyContent(FlexAlign.Center)
    }
    .hideTitleBar(true)
    .hideBackButton(true)
    .backgroundColor('#fffff2ea')
    .mode(NavigationMode.Stack)
  }
}