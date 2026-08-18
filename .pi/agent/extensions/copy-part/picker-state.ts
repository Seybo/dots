export class PickerState {
	readonly markedIndexes = new Set<number>();
	selectedIndex: number;
	private readonly itemCount: number;

	constructor(itemCount: number) {
		this.itemCount = itemCount;
		this.selectedIndex = 0;
	}

	move(offset: number): void {
		this.selectedIndex = (this.selectedIndex + offset + this.itemCount) % this.itemCount;
	}

	moveNext(): void {
		this.selectedIndex = Math.min(this.selectedIndex + 1, this.itemCount - 1);
	}

	toggleMark(): void {
		if (this.markedIndexes.has(this.selectedIndex)) this.markedIndexes.delete(this.selectedIndex);
		else this.markedIndexes.add(this.selectedIndex);
	}

	isMarked(index: number): boolean {
		return this.markedIndexes.has(index);
	}

	chosenItems(items: string[]): string[] {
		if (this.markedIndexes.size === 0) return [items[this.selectedIndex]!];

		return items.filter((_item, index) => this.markedIndexes.has(index));
	}
}
