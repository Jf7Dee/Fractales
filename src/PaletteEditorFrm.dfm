object PaletteEditorForm: TPaletteEditorForm
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = #201'diteur de palette'
  ClientHeight = 232
  ClientWidth = 620
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  KeyPreview = True
  OldCreateOrder = False
  Position = poOwnerFormCenter
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  OnKeyDown = FormKeyDown
  OnShow = FormShow
  PixelsPerInch = 96
  TextHeight = 15
  object lblName: TLabel
    Left = 12
    Top = 15
    Caption = 'Nom :'
  end
  object lblHelp: TLabel
    Left = 12
    Top = 128
    Caption = 
      'Glisser un point pour le d'#233'placer ; double-clic pour ajouter un point ou ' +
      'changer sa couleur ; Suppr pour l'#39'effacer.'
  end
  object pbGradient: TPaintBox
    Left = 12
    Top = 44
    Width = 596
    Height = 78
    OnMouseDown = pbGradientMouseDown
    OnMouseMove = pbGradientMouseMove
    OnMouseUp = pbGradientMouseUp
    OnPaint = pbGradientPaint
  end
  object edName: TEdit
    Left = 60
    Top = 11
    Width = 250
    Height = 23
    TabOrder = 0
    OnChange = edNameChange
  end
  object btnColor: TButton
    Left = 12
    Top = 156
    Width = 100
    Height = 26
    Caption = 'Couleur...'
    TabOrder = 1
    OnClick = btnColorClick
  end
  object btnDelete: TButton
    Left = 118
    Top = 156
    Width = 100
    Height = 26
    Caption = 'Supprimer'
    TabOrder = 2
    OnClick = btnDeleteClick
  end
  object btnLoad: TButton
    Left = 224
    Top = 156
    Width = 100
    Height = 26
    Caption = 'Charger...'
    TabOrder = 3
    OnClick = btnLoadClick
  end
  object btnSave: TButton
    Left = 330
    Top = 156
    Width = 100
    Height = 26
    Caption = 'Enregistrer...'
    TabOrder = 4
    OnClick = btnSaveClick
  end
  object btnImportMap: TButton
    Left = 436
    Top = 156
    Width = 120
    Height = 26
    Caption = 'Importer .map...'
    TabOrder = 5
    OnClick = btnImportMapClick
  end
  object btnOK: TButton
    Left = 452
    Top = 196
    Width = 75
    Height = 26
    Caption = 'OK'
    Default = True
    ModalResult = 1
    TabOrder = 6
  end
  object btnCancel: TButton
    Left = 533
    Top = 196
    Width = 75
    Height = 26
    Cancel = True
    Caption = 'Annuler'
    ModalResult = 2
    TabOrder = 7
  end
  object dlgColor: TColorDialog
    Options = [cdFullOpen]
    Left = 560
    Top = 4
  end
  object dlgOpen: TOpenDialog
    Options = [ofHideReadOnly, ofFileMustExist, ofEnableSizing]
    Left = 520
    Top = 4
  end
  object dlgSave: TSaveDialog
    DefaultExt = 'pal'
    Filter = 'Palette (*.pal)|*.pal'
    Options = [ofOverwritePrompt, ofHideReadOnly, ofEnableSizing]
    Left = 480
    Top = 4
  end
end
