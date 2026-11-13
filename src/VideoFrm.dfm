object VideoForm: TVideoForm
  Left = 0
  Top = 0
  BorderIcons = [biSystemMenu, biMinimize]
  BorderStyle = bsToolWindow
  Caption = 'Vid'#233'o'
  ClientHeight = 516
  ClientWidth = 760
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Menu = MainMenu1
  Position = poMainFormCenter
  OnActivate = FormActivate
  OnCloseQuery = FormCloseQuery
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  TextHeight = 15
  object lblSteps: TLabel
    Left = 8
    Top = 8
    Width = 34
    Height = 15
    Caption = #201'tapes'
  end
  object lblPreview: TLabel
    Left = 412
    Top = 8
    Width = 38
    Height = 15
    Caption = 'Aper'#231'u'
  end
  object imgPreview: TImage
    Left = 412
    Top = 26
    Width = 340
    Height = 192
    Center = True
    Proportional = True
    Stretch = True
  end
  object lblProgress: TLabel
    Left = 412
    Top = 286
    Width = 340
    Height = 30
    AutoSize = False
    WordWrap = True
  end
  object lblFfmpeg: TLabel
    Left = 412
    Top = 322
    Width = 340
    Height = 60
    AutoSize = False
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clMaroon
    Font.Height = -12
    Font.Name = 'Segoe UI'
    Font.Style = []
    ParentFont = False
    WordWrap = True
  end
  object lvSteps: TListView
    Left = 8
    Top = 26
    Width = 392
    Height = 216
    Columns = <
      item
        Caption = #201'tape'
        Width = 170
      end
      item
        Caption = 'Mode'
        Width = 70
      end
      item
        Caption = 'Trajet'
        Width = 64
      end
      item
        Caption = 'Pause'
        Width = 64
      end>
    HideSelection = False
    ReadOnly = True
    RowSelect = True
    TabOrder = 0
    ViewStyle = vsReport
    OnSelectItem = lvStepsSelectItem
  end
  object cbFavorites: TComboBox
    Left = 8
    Top = 250
    Width = 250
    Height = 23
    Style = csDropDownList
    TabOrder = 1
  end
  object btnAddFavorite: TButton
    Left = 264
    Top = 249
    Width = 136
    Height = 25
    Caption = 'Ajouter le favori'
    TabOrder = 2
    OnClick = btnAddFavoriteClick
  end
  object btnAddView: TButton
    Left = 8
    Top = 280
    Width = 130
    Height = 25
    Caption = 'Ajouter la vue'
    TabOrder = 3
    OnClick = btnAddViewClick
  end
  object btnRemove: TButton
    Left = 144
    Top = 280
    Width = 80
    Height = 25
    Caption = 'Retirer'
    TabOrder = 4
    OnClick = btnRemoveClick
  end
  object btnUp: TButton
    Left = 230
    Top = 280
    Width = 80
    Height = 25
    Caption = 'Monter'
    TabOrder = 5
    OnClick = btnUpClick
  end
  object btnDown: TButton
    Left = 316
    Top = 280
    Width = 84
    Height = 25
    Caption = 'Descendre'
    TabOrder = 6
    OnClick = btnDownClick
  end
  object gbStep: TGroupBox
    Left = 8
    Top = 314
    Width = 392
    Height = 104
    Caption = #201'tape choisie'
    TabOrder = 7
    object lblMode: TLabel
      Left = 12
      Top = 24
      Width = 44
      Height = 15
      Caption = 'Trajet en'
    end
    object lblTravel: TLabel
      Left = 12
      Top = 54
      Width = 47
      Height = 15
      Caption = 'Dur'#233'e (s)'
    end
    object lblPause: TLabel
      Left = 210
      Top = 54
      Width = 47
      Height = 15
      Caption = 'Pause (s)'
    end
    object lblSpeed: TLabel
      Left = 12
      Top = 80
      Width = 370
      Height = 15
      AutoSize = False
      WordWrap = True
    end
    object cbMode: TComboBox
      Left = 90
      Top = 20
      Width = 110
      Height = 23
      Style = csDropDownList
      TabOrder = 0
      OnChange = StepChange
    end
    object edTravel: TEdit
      Left = 90
      Top = 50
      Width = 60
      Height = 23
      TabOrder = 1
      OnChange = StepChange
    end
    object edPause: TEdit
      Left = 280
      Top = 50
      Width = 60
      Height = 23
      TabOrder = 2
      OnChange = StepChange
    end
    object cbStop: TCheckBox
      Left = 210
      Top = 22
      Width = 80
      Height = 19
      Caption = 'Arr'#234't'
      TabOrder = 3
      OnClick = StepChange
    end
  end
  object gbVideo: TGroupBox
    Left = 8
    Top = 424
    Width = 392
    Height = 84
    Caption = 'Vid'#233'o'
    TabOrder = 8
    object lblFormat: TLabel
      Left = 12
      Top = 24
      Width = 38
      Height = 15
      Caption = 'Format'
    end
    object lblSmoothing: TLabel
      Left = 12
      Top = 54
      Width = 38
      Height = 15
      Caption = 'Lissage'
    end
    object lblDuration: TLabel
      Left = 250
      Top = 24
      Width = 136
      Height = 45
      AutoSize = False
      WordWrap = True
    end
    object cbFormat: TComboBox
      Left = 90
      Top = 20
      Width = 150
      Height = 23
      Style = csDropDownList
      TabOrder = 0
      OnChange = VideoSettingsChange
    end
    object cbSmoothing: TComboBox
      Left = 90
      Top = 50
      Width = 150
      Height = 23
      Style = csDropDownList
      TabOrder = 1
      OnChange = VideoSettingsChange
    end
  end
  object btnPreview: TButton
    Left = 412
    Top = 226
    Width = 110
    Height = 25
    Caption = 'Aper'#231'u'
    TabOrder = 9
    OnClick = btnPreviewClick
  end
  object btnRender: TButton
    Left = 528
    Top = 226
    Width = 110
    Height = 25
    Caption = 'Cr'#233'er la vid'#233'o...'
    TabOrder = 10
    OnClick = btnRenderClick
  end
  object btnCancel: TButton
    Left = 644
    Top = 226
    Width = 108
    Height = 25
    Caption = 'Interrompre'
    TabOrder = 11
    OnClick = btnCancelClick
  end
  object pbProgress: TProgressBar
    Left = 412
    Top = 262
    Width = 340
    Height = 18
    TabOrder = 12
  end
  object btnReplay: TButton
    Left = 412
    Top = 390
    Width = 150
    Height = 25
    Caption = 'Revoir l'#39'aper'#231'u'
    TabOrder = 13
    OnClick = btnReplayClick
  end
  object tmrProgress: TTimer
    Enabled = False
    Interval = 250
    OnTimer = tmrProgressTimer
    Left = 700
    Top = 400
  end
  object dlgOpen: TOpenDialog
    Options = [ofHideReadOnly, ofFileMustExist, ofEnableSizing]
    Left = 620
    Top = 400
  end
  object dlgSave: TSaveDialog
    Options = [ofOverwritePrompt, ofHideReadOnly, ofEnableSizing]
    Left = 580
    Top = 400
  end
  object dlgVideo: TSaveDialog
    Options = [ofOverwritePrompt, ofHideReadOnly, ofEnableSizing]
    Left = 540
    Top = 400
  end
  object MainMenu1: TMainMenu
    Left = 368
    Top = 8
    object Fichier1: TMenuItem
      Caption = 'Fichier'
      object Ouvrir1: TMenuItem
        Action = Action_Open
      end
      object Enregistrer1: TMenuItem
        Action = Action_SaveAs
      end
      object Enregistrer2: TMenuItem
        Action = Action_Save
      end
      object N1: TMenuItem
        Caption = '-'
      end
      object Nouveau1: TMenuItem
        Action = Action_Reset
      end
      object N2: TMenuItem
        Caption = '-'
      end
      object ActionClose1: TMenuItem
        Action = Action_Close
      end
    end
  end
  object ActionList1: TActionList
    Left = 272
    Top = 96
    object Action_Open: TAction
      Caption = 'Ouvrir...'
      OnExecute = Action_OpenExecute
    end
    object Action_Save: TAction
      Caption = 'Enregistrer'
      ShortCut = 16467
      OnExecute = Action_SaveExecute
    end
    object Action_SaveAs: TAction
      Caption = 'Enregistrer...'
      OnExecute = Action_SaveAsExecute
    end
    object Action_Close: TAction
      Caption = 'Fermer'
      OnExecute = Action_CloseExecute
    end
    object Action_Reset: TAction
      Caption = 'Nouveau'
      OnExecute = Action_ResetExecute
    end
  end
end
