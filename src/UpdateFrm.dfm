object UpdateForm: TUpdateForm
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = 'Mise '#224' jour'
  ClientHeight = 190
  ClientWidth = 470
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
  object lblMessage: TLabel
    Left = 12
    Top = 15
    Width = 446
    Height = 38
    AutoSize = False
    WordWrap = True
  end
  object lblNotes: TLabel
    Left = 12
    Top = 59
    Width = 446
    Height = 100
    AutoSize = False
    WordWrap = True
  end
  object pbProgress: TProgressBar
    Left = 12
    Top = 70
    Width = 446
    Height = 20
    Max = 1000
    TabOrder = 0
    Visible = False
  end
  object btnUpdate: TButton
    Left = 287
    Top = 152
    Width = 90
    Height = 26
    Caption = 'Mettre '#224' jour'
    Default = True
    TabOrder = 1
    OnClick = btnUpdateClick
  end
  object btnLater: TButton
    Left = 383
    Top = 152
    Width = 75
    Height = 26
    Caption = 'Plus tard'
    TabOrder = 2
    OnClick = btnLaterClick
  end
  object btnCancel: TButton
    Left = 383
    Top = 152
    Width = 75
    Height = 26
    Caption = 'Annuler'
    TabOrder = 3
    Visible = False
    OnClick = btnCancelClick
  end
end
