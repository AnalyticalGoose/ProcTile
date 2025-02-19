class_name AssetPreview
extends PanelContainer

@export var preview_texture : TextureRect
@export var preview_label : Label


func set_properties(asset_texture : CompressedTexture2D, asset_name : String) -> void:
	preview_texture.texture = asset_texture
	preview_label.text = asset_name
