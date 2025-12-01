import WordData from '../../models/WordData';
import { RectangularText } from '../atoms/RectangularText';
import { CardBack } from '../molecules/CardBack';
import { CardFront } from '../molecules/CardFront'

@Component
export struct FlashCard {
  @Link public wordData: WordData;
  @Link public isActive: boolean;
  @Link swiped: boolean;
  @Link swipeDirection: boolean; // right = true, left = false
  @State private front: boolean = true
  public rotationCount: number = 0
  @State private rotation: number = 0
  private uiCtx: UIContext | null = null;
  startX: number = 0;
  @State cardRotation: number = 0;
  cardBackRotationSpeed: number = 2;

  @State opacityRight: number = 0;

  aboutToAppear() {
    this.uiCtx = this.getUIContext();
  }

  private swipeAndDo(rotation: number, func: () => void): void {
    if (!this.uiCtx) {
      return;
    }
    this.uiCtx.animateTo({
      duration: 250,
      curve: Curve.EaseIn,
      onFinish: () => {
        func()
      },
    }, () => {
      this.cardRotation = rotation
    });
  }

  swipeRight() {
    this.swipeAndDo(180, () => {
      this.cardRotation = 0
      this.swipeDirection = true
      this.swiped = true
      this.opacityRight = 0
      this.front = true
    });
  }

  swipeLeft() {
    this.swipeAndDo(-180, () => {
      this.cardRotation = 0
      this.swipeDirection = false
      this.swiped = true
      this.opacityRight = 0
      this.front = true
    });
  }

  animateBack() {
    this.swipeAndDo(0, () => {
      this.opacityRight = 0
    });
  }

  public rotateCard(): void {
    if (!this.uiCtx) {
      return;
    }
    this.uiCtx.animateTo({
      duration: 250,
      curve: Curve.EaseIn,
      onFinish: () => {
        this.front = !this.front;
        this.rotationCount++;

        this.uiCtx?.animateTo(
          {
            duration: 250,
            curve: Curve.EaseOut,
          },
          () => {
            this.rotation = 0;
          }
        );
      },
    }, () => {
      this.rotation = 90;
    });
  }

  build() {
    Column() {
      Stack() {

        Column() {
          CardFront(this.wordData.article, this.wordData.word, this.wordData.example)
        }
        .visibility(this.front ? Visibility.Visible : Visibility.Hidden)

        Column() {
          CardBack(this.wordData.article, this.wordData.word, this.wordData.example, this.wordData.meaning)
        }
        .visibility(!this.front ? Visibility.Visible : Visibility.Hidden)

        Column() {
          RectangularText(`Got it`, 15, Color.Green)
        }
        .width('100%')
        .height('100%')
        .rotate({
          angle: -40
        })
        .opacity(this.opacityRight)

        Column() {
          RectangularText(`Study again`, 15, Color.Red)
        }
        .width('100%')
        .height('100%')
        .rotate({
          angle: 40
        })
        .opacity(-this.opacityRight)
      }
      .onClick((event: ClickEvent) => {
        if (this.isActive) {
          this.rotateCard()
        }
      })
      .rotate({
        y: 1,
        angle: this.rotation,
        perspective: -800
      })
      .backgroundColor(Color.White)
      .borderRadius(10)
      .borderColor(Color.Black)
      .borderWidth(2)
    }
    .rotate({ angle: this.cardRotation, centerY: 1000 })
    .onTouch((event: TouchEvent) => {
      if (!event || !this.isActive || this.rotationCount == 0) {
        return;
      }
      const rotationThreshold: number = 5
      switch (event.type) {
        case TouchType.Down:
          this.startX = event.touches[0].displayX;
          break;
        case TouchType.Move:
          if (!this.swiped) {
            this.cardRotation = (event.touches[0].displayX - this.startX) / 10;
            this.opacityRight = this.cardRotation / 5;
          }
          break;
        case TouchType.Up:
          if (this.cardRotation > rotationThreshold) {
            this.swipeRight()
          } else if (this.cardRotation < -rotationThreshold) {
            this.swipeLeft()
          } else {
            this.animateBack()
          }
          break;
      }
    })
  }
}