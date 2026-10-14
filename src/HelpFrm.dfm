object HelpForm: THelpForm
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = 'Aide'
  ClientHeight = 300
  ClientWidth = 560
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  OldCreateOrder = False
  Position = poOwnerFormCenter
  OnShow = FormShow
  PixelsPerInch = 96
  TextHeight = 15
  object lblNote: TLabel
    Left = 12
    Top = 222
    Width = 536
    Height = 30
    AutoSize = False
    WordWrap = True
  end
  object lvHelp: TListView
    Left = 12
    Top = 12
    Width = 536
    Height = 200
    Columns = <
      item
        Caption = 'Action'
        Width = 300
      end
      item
        Caption = 'Commande'
        Width = 212
      end>
    ReadOnly = True
    RowSelect = True
    TabOrder = 0
    ViewStyle = vsReport
  end
  object btnClose: TButton
    Left = 473
    Top = 262
    Width = 75
    Height = 26
    Cancel = True
    Caption = 'Fermer'
    Default = True
    ModalResult = 1
    TabOrder = 1
  end
end
