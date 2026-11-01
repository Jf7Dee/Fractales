object AboutForm: TAboutForm
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = #192' propos de Fractales'
  ClientHeight = 150
  ClientWidth = 380
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  OldCreateOrder = False
  Position = poMainFormCenter
  OnCloseQuery = FormCloseQuery
  OnDestroy = FormDestroy
  PixelsPerInch = 96
  TextHeight = 15
  object lblTitle: TLabel
    Left = 12
    Top = 12
    Width = 356
    Height = 25
    AutoSize = False
    Caption = 'Fractales'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -19
    Font.Name = 'Segoe UI'
    Font.Style = [fsBold]
    ParentFont = False
  end
  object lblVersion: TLabel
    Left = 12
    Top = 42
    Width = 356
    Height = 15
    AutoSize = False
  end
  object lblStatus: TLabel
    Left = 12
    Top = 66
    Width = 356
    Height = 40
    AutoSize = False
    WordWrap = True
  end
  object btnCheck: TButton
    Left = 112
    Top = 114
    Width = 175
    Height = 26
    Caption = 'Rechercher une mise '#224' jour'
    Default = True
    TabOrder = 0
    OnClick = btnCheckClick
  end
  object btnClose: TButton
    Left = 293
    Top = 114
    Width = 75
    Height = 26
    Cancel = True
    Caption = 'Fermer'
    TabOrder = 1
    OnClick = btnCloseClick
  end
end
