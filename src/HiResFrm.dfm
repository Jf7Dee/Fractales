object HiResForm: THiResForm
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = 'Rendu haute r'#233'solution'
  ClientHeight = 250
  ClientWidth = 470
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  OldCreateOrder = False
  Position = poOwnerFormCenter
  OnCloseQuery = FormCloseQuery
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  PixelsPerInch = 96
  TextHeight = 15
  object lblPreset: TLabel
    Left = 12
    Top = 15
    Caption = 'Taille :'
  end
  object lblSize: TLabel
    Left = 12
    Top = 47
    Caption = 'Largeur x hauteur :'
  end
  object lblSupersample: TLabel
    Left = 12
    Top = 79
    Caption = 'Sur'#233'chantillonnage :'
  end
  object lblFile: TLabel
    Left = 12
    Top = 111
    Caption = 'Fichier :'
  end
  object lblState: TLabel
    Left = 12
    Top = 180
    Width = 446
    Height = 15
    AutoSize = False
  end
  object cbPreset: TComboBox
    Left = 150
    Top = 11
    Width = 308
    Height = 23
    Style = csDropDownList
    TabOrder = 0
    OnChange = cbPresetChange
  end
  object edWidth: TEdit
    Left = 150
    Top = 43
    Width = 80
    Height = 23
    TabOrder = 1
  end
  object edHeight: TEdit
    Left = 240
    Top = 43
    Width = 80
    Height = 23
    TabOrder = 2
  end
  object cbSupersample: TComboBox
    Left = 150
    Top = 75
    Width = 200
    Height = 23
    Style = csDropDownList
    TabOrder = 3
  end
  object edFile: TEdit
    Left = 150
    Top = 107
    Width = 270
    Height = 23
    TabOrder = 4
  end
  object btnBrowse: TButton
    Left = 426
    Top = 106
    Width = 32
    Height = 25
    Caption = '...'
    TabOrder = 5
    OnClick = btnBrowseClick
  end
  object pbProgress: TProgressBar
    Left = 12
    Top = 150
    Width = 446
    Height = 20
    Max = 1000
    TabOrder = 6
  end
  object btnStart: TButton
    Left = 302
    Top = 212
    Width = 75
    Height = 26
    Caption = 'D'#233'marrer'
    Default = True
    TabOrder = 7
    OnClick = btnStartClick
  end
  object btnClose: TButton
    Left = 383
    Top = 212
    Width = 75
    Height = 26
    Caption = 'Fermer'
    TabOrder = 8
    OnClick = btnCloseClick
  end
  object tmrPoll: TTimer
    Enabled = False
    Interval = 200
    OnTimer = tmrPollTimer
    Left = 12
    Top = 208
  end
  object dlgSave: TSaveDialog
    DefaultExt = 'png'
    Filter = 'Image PNG (*.png)|*.png'
    Options = [ofOverwritePrompt, ofHideReadOnly, ofEnableSizing]
    Left = 50
    Top = 208
  end
end
