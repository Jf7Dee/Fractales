unit TestFractalBuffer;

interface

uses
  TestFramework, Fractal.Types, Fractal.Buffer;

type
  TTestBuffer = class(TTestCase)
  published
    procedure TestNewBufferIsNotComputed;
    procedure TestWriteAnchorFillsBlock;
    procedure TestCoarseBlockKeepsFinerPixels;
    procedure TestBlockIsClippedAtEdges;
    procedure TestShiftMovesContent;
    procedure TestDirtyFlag;
  end;

implementation

{------------------------------------------------------------------------------}

procedure TTestBuffer.TestNewBufferIsNotComputed;
var
  B: TIterationBuffer;
begin
  B := TIterationBuffer.Create(10, 8);
  try
    CheckEquals(10, B.Width);
    CheckEquals(8, B.Height);
    CheckEquals(kNotComputed, B.Value(9, 7), 0);
    CheckEquals(0, B.Level(9, 7));
  finally
    B.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestBuffer.TestWriteAnchorFillsBlock;
var
  B: TIterationBuffer;
begin
  B := TIterationBuffer.Create(16, 16);
  try
    B.WriteAnchor(0, 0, 4, 5);
    CheckTrue(B.IsExact(0, 0));
    CheckEquals(4, B.Level(3, 3));
    CheckEquals(5.0, B.Value(3, 3), 0);
    CheckEquals(0, B.Level(4, 0));
    B.WriteAnchor(2, 0, 2, 9);
    CheckTrue(B.IsExact(2, 0));
    CheckEquals(2, B.Level(3, 1));
    CheckEquals(9.0, B.Value(3, 1), 0);
    CheckEquals(4, B.Level(0, 1));
  finally
    B.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestBuffer.TestCoarseBlockKeepsFinerPixels;
var
  B: TIterationBuffer;
begin
  B := TIterationBuffer.Create(16, 16);
  try
    B.WriteAnchor(1, 1, 1, 7);
    B.WriteAnchor(0, 0, 4, 3);
    CheckEquals(7.0, B.Value(1, 1), 0);
    CheckTrue(B.IsExact(1, 1));
    CheckEquals(3.0, B.Value(2, 2), 0);
    CheckEquals(4, B.Level(2, 2));
  finally
    B.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestBuffer.TestBlockIsClippedAtEdges;
var
  B: TIterationBuffer;
begin
  B := TIterationBuffer.Create(5, 5);
  try
    B.WriteAnchor(0, 0, 8, 2);
    CheckEquals(2.0, B.Value(4, 4), 0);
    CheckEquals(8, B.Level(4, 4));
  finally
    B.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestBuffer.TestShiftMovesContent;
var
  B: TIterationBuffer;
begin
  B := TIterationBuffer.Create(8, 8);
  try
    B.WriteAnchor(1, 1, 1, 5);
    B.Shift(2, 1);
    CheckEquals(5.0, B.Value(3, 2), 0);
    CheckTrue(B.IsExact(3, 2));
    CheckEquals(kNotComputed, B.Value(0, 0), 0);
    CheckEquals(0, B.Level(0, 0));
  finally
    B.Free;
  end;
end;

{------------------------------------------------------------------------------}

procedure TTestBuffer.TestDirtyFlag;
var
  B: TIterationBuffer;
begin
  B := TIterationBuffer.Create(2, 2);
  try
    B.TakeDirtyFlag;
    CheckFalse(B.TakeDirtyFlag);
    B.MarkDirty;
    CheckTrue(B.TakeDirtyFlag);
    CheckFalse(B.TakeDirtyFlag);
  finally
    B.Free;
  end;
end;

initialization
  RegisterTest(TTestBuffer.Suite);

end.
