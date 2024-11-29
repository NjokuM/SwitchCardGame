extends Node2D

var card_in_slot = true

func DisableCardSlotImage():
	if card_in_slot:
		$CardSlotImage.visible = false
	
