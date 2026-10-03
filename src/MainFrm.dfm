object MainForm: TMainForm
  Left = 0
  Top = 0
  Caption = 'Fractales'
  ClientHeight = 720
  ClientWidth = 1200
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  KeyPreview = True
  OldCreateOrder = False
  Position = poScreenCenter
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  OnKeyDown = FormKeyDown
  PixelsPerInch = 96
  TextHeight = 15
  object pnlTop: TPanel
    Left = 0
    Top = 0
    Width = 1200
    Height = 34
    Align = alTop
    BevelOuter = bvNone
    TabOrder = 0
    object lblNavMode: TLabel
      Left = 376
      Top = 9
      Caption = 'Navigation :'
    end
    object btnOpen: TButton
      Left = 4
      Top = 4
      Width = 80
      Height = 26
      Caption = 'Ouvrir...'
      TabOrder = 0
    end
    object btnSave: TButton
      Left = 88
      Top = 4
      Width = 90
      Height = 26
      Caption = 'Enregistrer...'
      TabOrder = 1
    end
    object btnExportPng: TButton
      Left = 182
      Top = 4
      Width = 70
      Height = 26
      Caption = 'PNG...'
      TabOrder = 2
    end
    object btnHiRes: TButton
      Left = 256
      Top = 4
      Width = 100
      Height = 26
      Caption = 'Rendu HD...'
      TabOrder = 3
    end
    object cbNavMode: TComboBox
      Left = 452
      Top = 5
      Width = 130
      Height = 23
      Style = csDropDownList
      TabOrder = 4
    end
    object btnBack: TButton
      Left = 592
      Top = 4
      Width = 34
      Height = 26
      Hint = 'Pr'#233'c'#233'dent (Retour arri'#232're)'
      Caption = #9668
      ParentShowHint = False
      ShowHint = True
      TabOrder = 5
    end
    object btnForward: TButton
      Left = 628
      Top = 4
      Width = 34
      Height = 26
      Hint = 'Suivant'
      Caption = #9658
      ParentShowHint = False
      ShowHint = True
      TabOrder = 6
    end
    object btnAddFavorite: TButton
      Left = 672
      Top = 4
      Width = 90
      Height = 26
      Caption = #9733' Favori'
      TabOrder = 7
    end
    object btnTogglePanel: TButton
      Left = 766
      Top = 4
      Width = 100
      Height = 26
      Caption = 'Panneau (F4)'
      TabOrder = 8
    end
  end
  object sbStatus: TStatusBar
    Left = 0
    Top = 701
    Width = 1200
    Height = 19
    Panels = <
      item
        Width = 320
      end
      item
        Width = 130
      end
      item
        Width = 100
      end
      item
        Width = 170
      end
      item
        Width = 50
      end>
  end
  object pnlSide: TPanel
    Left = 920
    Top = 34
    Width = 280
    Height = 667
    Align = alRight
    BevelOuter = bvNone
    TabOrder = 1
    object grpFormula: TGroupBox
      Left = 0
      Top = 0
      Width = 280
      Height = 210
      Align = alTop
      Caption = 'Formule'
      TabOrder = 0
      object lblMaxIter: TLabel
        Left = 8
        Top = 180
        Caption = 'It'#233'rations max'
      end
      object cbFormula: TComboBox
        Left = 8
        Top = 20
        Width = 262
        Height = 23
        Style = csDropDownList
        TabOrder = 0
      end
      object pnlParams: TPanel
        Left = 8
        Top = 50
        Width = 262
        Height = 120
        BevelOuter = bvNone
        TabOrder = 1
      end
      object edMaxIter: TEdit
        Left = 100
        Top = 176
        Width = 80
        Height = 23
        TabOrder = 2
      end
      object chkAutoIter: TCheckBox
        Left = 190
        Top = 179
        Width = 70
        Height = 17
        Caption = 'auto'
        TabOrder = 3
      end
    end
    object grpColors: TGroupBox
      Left = 0
      Top = 210
      Width = 280
      Height = 185
      Align = alTop
      Caption = 'Couleurs'
      TabOrder = 1
      object lblOffset: TLabel
        Left = 8
        Top = 56
        Caption = 'D'#233'calage'
      end
      object lblRepeats: TLabel
        Left = 8
        Top = 88
        Caption = 'R'#233'p'#233'tition'
      end
      object lblStretch: TLabel
        Left = 8
        Top = 120
        Caption = #201'tirement'
      end
      object cbPalette: TComboBox
        Left = 8
        Top = 20
        Width = 180
        Height = 23
        Style = csDropDownList
        TabOrder = 0
      end
      object btnEditPalette: TButton
        Left = 194
        Top = 19
        Width = 76
        Height = 25
        Caption = #201'diter...'
        TabOrder = 1
      end
      object tbOffset: TTrackBar
        Left = 80
        Top = 50
        Width = 190
        Height = 26
        Max = 1000
        TabOrder = 2
        TickStyle = tsNone
      end
      object tbRepeats: TTrackBar
        Left = 80
        Top = 82
        Width = 190
        Height = 26
        Max = 1000
        TabOrder = 3
        TickStyle = tsNone
      end
      object tbStretch: TTrackBar
        Left = 80
        Top = 114
        Width = 190
        Height = 26
        Max = 1000
        TabOrder = 4
        TickStyle = tsNone
      end
      object chkInvert: TCheckBox
        Left = 8
        Top = 152
        Width = 120
        Height = 17
        Caption = 'Inverser'
        TabOrder = 5
      end
    end
    object grpFavorites: TGroupBox
      Left = 0
      Top = 395
      Width = 280
      Height = 272
      Align = alClient
      Caption = 'Favoris'
      TabOrder = 2
      object lbFavorites: TListBox
        AlignWithMargins = True
        Left = 5
        Top = 20
        Width = 270
        Height = 247
        Align = alClient
        ItemHeight = 15
        TabOrder = 0
      end
    end
  end
  object splSide: TSplitter
    Left = 915
    Top = 34
    Width = 5
    Height = 667
    Align = alRight
    MinSize = 200
  end
  object pnlCollapse: TPanel
    Left = 899
    Top = 34
    Width = 16
    Height = 667
    Align = alRight
    BevelOuter = bvNone
    TabOrder = 2
    object btnCollapse: TSpeedButton
      Left = 0
      Top = 0
      Width = 16
      Height = 667
      Hint = 'Masquer / afficher le panneau (F4)'
      Align = alClient
      Caption = #9656
      Flat = True
      ParentShowHint = False
      ShowHint = True
    end
  end
  object tmrDisplay: TTimer
    Interval = 33
    Left = 40
    Top = 80
  end
end
